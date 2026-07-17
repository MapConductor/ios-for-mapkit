import MapKit
import MapConductorCore

@MainActor
final class MapKitRasterLayerOverlayRenderer: AbstractRasterLayerOverlayRenderer<MKTileOverlay> {
    private weak var mapView: MKMapView?
    private var renderersByLayerId: [String: MKTileOverlayRenderer] = [:]
    private var overlayStates: [MKTileOverlay: RasterLayerState] = [:]

    init(mapView: MKMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createLayer(state: RasterLayerState) async -> MKTileOverlay? {
        guard let mapView else { return nil }
        guard let overlay = await makeTileOverlay(from: state) else { return nil }
        overlayStates[overlay] = state

        let renderer = MKTileOverlayRenderer(tileOverlay: overlay)
        renderer.alpha = CGFloat(state.opacity)
        renderersByLayerId[state.id] = renderer

        // Important: MapKit may request a renderer immediately as part of addOverlay().
        // Ensure we have the renderer registered before adding the overlay to the map.
        if state.visible {
            mapView.addOverlay(overlay, level: .aboveLabels)
        }

        return overlay
    }

    override func updateLayerProperties(
        layer: MKTileOverlay,
        current: RasterLayerEntity<MKTileOverlay>,
        prev: RasterLayerEntity<MKTileOverlay>
    ) async -> MKTileOverlay? {
        guard let mapView else { return layer }
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        if finger.source != prevFinger.source {
            mapView.removeOverlay(layer)
            renderersByLayerId.removeValue(forKey: prev.state.id)
            overlayStates.removeValue(forKey: layer)
            return await createLayer(state: current.state)
        }

        if finger.opacity != prevFinger.opacity {
            if let renderer = renderersByLayerId[current.state.id] {
                renderer.alpha = CGFloat(current.state.opacity)
                renderer.setNeedsDisplay()
            }
        }

        if finger.visible != prevFinger.visible {
            if current.state.visible {
                if layer.isKind(of: MKTileOverlay.self) && !mapView.overlays.contains(where: { $0 === layer }) {
                    mapView.addOverlay(layer, level: .aboveLabels)
                }
            } else {
                mapView.removeOverlay(layer)
            }
        }

        overlayStates[layer] = current.state

        return layer
    }

    override func removeLayer(entity: RasterLayerEntity<MKTileOverlay>) async {
        guard let mapView, let layer = entity.layer else { return }
        mapView.removeOverlay(layer)
        renderersByLayerId.removeValue(forKey: entity.state.id)
        overlayStates.removeValue(forKey: layer)
    }

    func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        guard let tileOverlay = overlay as? MKTileOverlay,
              let state = overlayStates[tileOverlay],
              let renderer = renderersByLayerId[state.id] ?? {
                  // Fallback: if MapKit asked for the renderer before we registered it (or after eviction),
                  // create one on demand so the overlay can still render.
                  let created = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                  created.alpha = CGFloat(state.opacity)
                  renderersByLayerId[state.id] = created
                  return created
              }() else {
            return nil
        }
        return renderer
    }

    func unbind() {
        renderersByLayerId.removeAll()
        overlayStates.removeAll()
        mapView = nil
    }

    private func makeTileOverlay(from state: RasterLayerState) async -> MKTileOverlay? {
        let source = await resolveSource(state: state)

        switch source {
        case let .urlTemplate(template, tileSize, minZoom, maxZoom, _, scheme):
            let overlay = CustomURLTileOverlay(
                urlTemplate: template,
                tileSize: tileSize,
                minZoom: minZoom,
                maxZoom: maxZoom,
                scheme: scheme,
                userAgent: state.userAgent,
                extraHeaders: state.extraHeaders
            )
            // Set canReplaceMapContent to false for overlay layers (like heatmaps)
            // so the base map remains visible underneath
            overlay.canReplaceMapContent = false
            return overlay
        case .tileJson:
            // TileJSON is resolved to a UrlTemplate before reaching here.
            return nil
        case .arcGisService:
            // ArcGIS is resolved to a UrlTemplate before reaching here.
            return nil
        }
    }

    private struct TileJson: Decodable {
        let tiles: [String]
        let minzoom: Int?
        let maxzoom: Int?
        let tileSize: Int?
        let scheme: String?

        enum CodingKeys: String, CodingKey {
            case tiles
            case minzoom
            case maxzoom
            case tileSize = "tileSize"
            case scheme
        }
    }

    private func resolveSource(state: RasterLayerState) async -> RasterSource {
        switch state.source {
        case .urlTemplate:
            return state.source
        case let .arcGisService(serviceUrl):
            let base = serviceUrl.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let template = "\(base)/tile/{z}/{y}/{x}"
            return .urlTemplate(template: template, tileSize: RasterSource.defaultTileSize, scheme: .XYZ)
        case let .tileJson(url):
            guard let configUrl = URL(string: url) else {
                NSLog("[MapConductor] MapKit RasterLayer: invalid tileJson url=%@", url)
                return state.source
            }
            do {
                let tileJson = try await fetchTileJson(url: configUrl, state: state)
                guard let template = tileJson.tiles.first else {
                    NSLog("[MapConductor] MapKit RasterLayer: tileJson contained no tiles array. id=%@", state.id)
                    return state.source
                }
                let scheme: TileScheme =
                    (tileJson.scheme?.lowercased() == "tms") ? .TMS : .XYZ
                let tileSize = tileJson.tileSize ?? RasterSource.defaultTileSize
                return .urlTemplate(
                    template: template,
                    tileSize: tileSize,
                    minZoom: tileJson.minzoom,
                    maxZoom: tileJson.maxzoom,
                    attributionRules: [],
                    scheme: scheme
                )
            } catch {
                NSLog("[MapConductor] MapKit RasterLayer: failed to load tileJson. id=%@ error=%@", state.id, String(describing: error))
                return state.source
            }
        }
    }

    private func fetchTileJson(url: URL, state: RasterLayerState) async throws -> TileJson {
        var request = URLRequest(url: url)
        if let headers = state.extraHeaders {
            for (k, v) in headers {
                request.setValue(v, forHTTPHeaderField: k)
            }
        }
        let ua = state.userAgent?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if let ua, !ua.isEmpty {
            request.setValue(ua, forHTTPHeaderField: "User-Agent")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(
                domain: "MapConductorForMapKit.TileJson",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) for \(url.absoluteString)"]
            )
        }
        return try JSONDecoder().decode(TileJson.self, from: data)
    }
}

// Custom MKTileOverlay to support URL template pattern
private class CustomURLTileOverlay: MKTileOverlay {
    private let templateString: String
    private let minZoom: Int?
    private let maxZoom: Int?
    private let scheme: TileScheme
    private let session: URLSession
    private let userAgent: String?
    private let extraHeaders: [String: String]

    init(
        urlTemplate: String,
        tileSize: Int,
        minZoom: Int?,
        maxZoom: Int?,
        scheme: TileScheme,
        userAgent: String?,
        extraHeaders: [String: String]?
    ) {
        self.templateString = urlTemplate
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.scheme = scheme
        self.userAgent = userAgent
        self.extraHeaders = extraHeaders ?? [:]
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        super.init(urlTemplate: urlTemplate)
        self.tileSize = CGSize(width: max(1, tileSize), height: max(1, tileSize))

        // MKTileOverlay will not request tiles outside this range. If left unset, MapKit can end up
        // requesting only z=0 in some cases, making the layer appear blank at normal zooms.
        self.minimumZ = minZoom ?? 0
        self.maximumZ = maxZoom ?? 22
    }

    override var boundingMapRect: MKMapRect { MKMapRect.world }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, (any Error)?) -> Void) {
        let url = url(forTilePath: path)
        if url.scheme == "about" {
            result(nil, nil)
            return
        }

        var request = URLRequest(url: url)
        for (k, v) in extraHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }
        let ua = userAgent?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if let ua, !ua.isEmpty {
            request.setValue(ua, forHTTPHeaderField: "User-Agent")
        } else {
            // Some public tile servers require a clear User-Agent.
            request.setValue("MapConductor (iOS; MKTileOverlay)", forHTTPHeaderField: "User-Agent")
        }

        session.dataTask(with: request) { data, response, error in
            if let error {
                result(nil, error)
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let err = NSError(
                    domain: "MapConductorForMapKit.MKTileOverlay",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) for \(url.absoluteString)"]
                )
                result(nil, err)
                return
            }
            // Always return the original tile bytes. Most public raster tile servers (e.g. OSM)
            // provide 256px tiles; MapKit will scale as needed.
            result(data, nil)
        }.resume()
    }

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        // Check zoom level bounds
        if let minZoom, path.z < minZoom {
            return URL(string: "about:blank")!
        }
        if let maxZoom, path.z > maxZoom {
            return URL(string: "about:blank")!
        }

        let y: Int
        switch scheme {
        case .XYZ:
            y = path.y
        case .TMS:
            // Flip Y for TMS.
            let maxIndex = (1 << path.z) - 1
            y = maxIndex - path.y
        }

        let urlString = templateString
            .replacingOccurrences(of: "{z}", with: String(path.z))
            .replacingOccurrences(of: "{x}", with: String(path.x))
            .replacingOccurrences(of: "{y}", with: String(y))

        return URL(string: urlString) ?? URL(string: "about:blank")!
    }
}
