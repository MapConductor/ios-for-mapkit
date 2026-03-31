import Combine
import CoreLocation
import MapKit
import MapConductorCore

@MainActor
final class MapKitMarkerController: AbstractMarkerController<MKPointAnnotation, MapKitMarkerRenderer> {
    private weak var mapView: MKMapView?

    private var markerStatesById: [String: MarkerState] = [:]
    private var markerSubscriptions: [String: AnyCancellable] = [:]

    private let onUpdateInfoBubble: (String) -> Void

    init(mapView: MKMapView?, onUpdateInfoBubble: @escaping (String) -> Void) {
        self.mapView = mapView
        self.onUpdateInfoBubble = onUpdateInfoBubble

        let markerManager = MarkerManager<MKPointAnnotation>.defaultManager()
        let renderer = MapKitMarkerRenderer(mapView: mapView, markerManager: markerManager)
        super.init(markerManager: markerManager, renderer: renderer)
    }

    func syncMarkers(_ markers: [Marker]) {
        MCLog.marker("MapKitMarkerController.syncMarkers count=\(markers.count)")
        let newIds = Set(markers.map { $0.id })
        let oldIds = Set(markerStatesById.keys)

        var newStatesById: [String: MarkerState] = [:]
        var shouldSyncList = false

        for marker in markers {
            let state = marker.state
            if let existingState = markerStatesById[state.id], existingState !== state {
                markerSubscriptions[state.id]?.cancel()
                markerSubscriptions.removeValue(forKey: state.id)
                // State instance changed: ensure controller updates entity reference.
                shouldSyncList = true
            }
            newStatesById[state.id] = state
            if !markerManager.hasEntity(state.id) {
                shouldSyncList = true
            }
        }

        if oldIds != newIds {
            shouldSyncList = true
        }

        markerStatesById = newStatesById

        let removedIds = oldIds.subtracting(newIds)
        for id in removedIds {
            markerSubscriptions[id]?.cancel()
            markerSubscriptions.removeValue(forKey: id)
        }

        if shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                MCLog.marker("MapKitMarkerController.syncMarkers -> add()")
                await self.add(data: markers.map { $0.state })
            }
        } else {
            refreshTileLayerIfNeeded()
        }

        for marker in markers {
            subscribeToMarker(marker.state)
            onUpdateInfoBubble(marker.id)
        }
    }

    private func subscribeToMarker(_ state: MarkerState) {
        guard markerSubscriptions[state.id] == nil else { return }
        MCLog.marker("MapKitMarkerController.subscribe id=\(state.id)")
        markerSubscriptions[state.id] = state.asFlow()
            .dropFirst() // Skip initial value to avoid triggering update on subscription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.markerStatesById[state.id] != nil else { return }
                MCLog.marker("MapKitMarkerController.asFlow emit id=\(state.id) anim=\(String(describing: state.getAnimation()))")
                // Update InfoBubble immediately using the latest MarkerState values.
                // Renderer updates can be throttled/deferred, which otherwise makes the bubble lag behind rapid updates.
                self.onUpdateInfoBubble(state.id)
                Task { [weak self] in
                    guard let self else { return }
                    await self.update(state: state)
                    self.onUpdateInfoBubble(state.id)
                }
            }
    }

    func getMarkerState(for id: String) -> MarkerState? {
        markerManager.getEntity(id)?.state
    }

    func getIcon(for state: MarkerState) -> BitmapIcon {
        let resolvedIcon = state.icon ?? DefaultMarkerIcon()
        return resolvedIcon.toBitmapIcon()
    }

    // MARK: - Marker tiling

    var tilingOptions: MarkerTilingOptions = .Default
    private var tileRenderer: MarkerTileRenderer<MKPointAnnotation>?
    private var tileRouteId: String?
    private var tiledMarkerIds: Set<String> = []
    private var tileOverlay: MKTileOverlay?
    private var lastServerBaseUrl: String = ""
    private let defaultMarkerIconForTiling: BitmapIcon = DefaultMarkerIcon().toBitmapIcon()

    private static var retinaAwareTileSize: Int {
        256 * max(1, Int(UIScreen.main.scale))
    }

    private func setupTileRenderer() {
        let routeId = "mapconductor-markers-\(UUID().uuidString)"
        let contentScale = Double(UIScreen.main.scale)
        let baseCallback = tilingOptions.iconScaleCallback
        let scaledCallback: ((MarkerState, Int) -> Double)? = { state, zoom in
            (baseCallback?(state, zoom) ?? 1.0) * contentScale
        }
        MCLog.marker("MapKitMarkerController.setupTileRenderer tileSize=\(Self.retinaAwareTileSize) contentScale=\(contentScale) routeId=\(routeId)")
        let renderer = MarkerTileRenderer<MKPointAnnotation>(
            markerManager: markerManager,
            tileSize: Self.retinaAwareTileSize,
            cacheSizeBytes: tilingOptions.cacheSize,
            debugTileOverlay: tilingOptions.debugTileOverlay,
            iconScaleCallback: scaledCallback
        )
        TileServerRegistry.get().register(routeId: routeId, provider: renderer)
        tileRenderer = renderer
        tileRouteId = routeId
    }

    override func add(data: [MarkerState]) async {
        guard tilingOptions.enabled else {
            MCLog.marker("MapKitMarkerController.add tilingDisabled count=\(data.count)")
            await super.add(data: data)
            return
        }
        if tileRenderer == nil { setupTileRenderer() }

        let shouldTileAll = data.count >= tilingOptions.minMarkerCount
        MCLog.marker("MapKitMarkerController.add count=\(data.count) minMarkerCount=\(tilingOptions.minMarkerCount) shouldTileAll=\(shouldTileAll)")
        var localTiledMarkerIds = tiledMarkerIds
        let result = await MarkerIngestionEngine.ingest(
            data: data,
            markerManager: markerManager,
            renderer: renderer,
            defaultMarkerIcon: defaultMarkerIconForTiling,
            tilingEnabled: tilingOptions.enabled,
            tiledMarkerIds: &localTiledMarkerIds,
            shouldTile: { [shouldTileAll] _ in shouldTileAll }
        )
        tiledMarkerIds = localTiledMarkerIds
        MCLog.marker("MapKitMarkerController.add ingest done tiledDataChanged=\(result.tiledDataChanged) hasTiledMarkers=\(result.hasTiledMarkers) tiledCount=\(tiledMarkerIds.count)")

        if result.tiledDataChanged, let tileRenderer {
            tileRenderer.invalidate()
            updateTileOverlay(hasTiledMarkers: result.hasTiledMarkers)
        }
    }

    private func refreshTileLayerIfNeeded() {
        guard !tiledMarkerIds.isEmpty else { return }
        let server = TileServerRegistry.get()
        guard server.baseUrl != lastServerBaseUrl else { return }
        MCLog.marker("MapKitMarkerController.refreshTileLayerIfNeeded serverRestarted oldUrl=\(lastServerBaseUrl) newUrl=\(server.baseUrl)")
        updateTileOverlay(hasTiledMarkers: true)
    }

    private func updateTileOverlay(hasTiledMarkers: Bool) {
        MCLog.marker("MapKitMarkerController.updateTileOverlay hasTiledMarkers=\(hasTiledMarkers) mapView=\(mapView != nil) routeId=\(tileRouteId ?? "nil")")
        if let old = tileOverlay {
            mapView?.removeOverlay(old)
            tileOverlay = nil
        }

        guard hasTiledMarkers, let mapView, let routeId = tileRouteId, let tileRenderer else { return }

        let server = TileServerRegistry.get()
        lastServerBaseUrl = server.baseUrl
        let urlTemplate = server.urlTemplate(routeId: routeId, tileSize: tileRenderer.tileSize)
        MCLog.marker("MapKitMarkerController.updateTileOverlay addOverlay urlTemplate=\(urlTemplate) tileSize=\(tileRenderer.tileSize)")
        // MKTileOverlay.tileSize=256 ensures MapKit requests tiles at the correct zoom level.
        // The server returns retinaAwareTileSize images for Retina sharpness.
        let overlay = MarkerTileOverlay(urlTemplate: urlTemplate, tileSize: 256)
        mapView.addOverlay(overlay, level: .aboveLabels)
        tileOverlay = overlay
    }

    /// Hit-test tiled markers at the given screen point (pts). Returns true if a clickable marker was found.
    func handleTiledMarkerTap(at screenPoint: CGPoint) -> Bool {
        MCLog.marker("MapKitMarkerController.handleTiledMarkerTap point=\(screenPoint) tiledCount=\(tiledMarkerIds.count)")
        guard !tiledMarkerIds.isEmpty, let mapView else { return false }
        let clickRadiusPt: CGFloat = 44
        var bestState: MarkerState? = nil
        var bestDist = CGFloat.infinity

        for id in tiledMarkerIds {
            guard let entity = markerManager.getEntity(id), entity.state.clickable else { continue }
            let coord = CLLocationCoordinate2D(
                latitude: entity.state.position.latitude,
                longitude: entity.state.position.longitude
            )
            let markerPoint = mapView.convert(coord, toPointTo: mapView)
            let dist = hypot(screenPoint.x - markerPoint.x, screenPoint.y - markerPoint.y)
            if dist < clickRadiusPt && dist < bestDist {
                bestDist = dist
                bestState = entity.state
            }
        }

        if let state = bestState {
            MCLog.marker("MapKitMarkerController.handleTiledMarkerTap hit id=\(state.id) dist=\(bestDist)")
            dispatchClick(state: state)
            return true
        }
        MCLog.marker("MapKitMarkerController.handleTiledMarkerTap miss")
        return false
    }

    func tileOverlayRenderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        guard let tileOverlay = overlay as? MarkerTileOverlay, tileOverlay === self.tileOverlay else { return nil }
        let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
        return renderer
    }

    func unbind() {
        markerSubscriptions.values.forEach { $0.cancel() }
        markerSubscriptions.removeAll()
        markerStatesById.removeAll()
        if let old = tileOverlay {
            mapView?.removeOverlay(old)
            tileOverlay = nil
        }
        if let routeId = tileRouteId {
            TileServerRegistry.get().unregister(routeId: routeId)
        }
        tileRenderer = nil
        tileRouteId = nil
        tiledMarkerIds.removeAll()
        renderer.unbind()
        mapView = nil
        destroy()
    }
}

// Simple MKTileOverlay that fetches from the local tile server URL template.
final class MarkerTileOverlay: MKTileOverlay {
    init(urlTemplate: String, tileSize: Int) {
        super.init(urlTemplate: urlTemplate)
        self.tileSize = CGSize(width: tileSize, height: tileSize)
        self.minimumZ = 0
        self.maximumZ = 22
        self.canReplaceMapContent = false
    }

    override var boundingMapRect: MKMapRect { MKMapRect.world }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        MCLog.marker("MarkerTileOverlay.url z=\(path.z) x=\(path.x) y=\(path.y) scale=\(path.contentScaleFactor)")
        let base = super.url(forTilePath: path).absoluteString
        return URL(string: base) ?? URL(string: "about:blank")!
    }
}
