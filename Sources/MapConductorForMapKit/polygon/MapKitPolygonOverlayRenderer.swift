import MapKit
import MapConductorCore
import UIKit

@MainActor
final class MapKitPolygonOverlayRenderer: AbstractPolygonOverlayRenderer<MKPolygon> {
    private weak var mapView: MKMapView?
    private var renderersByPolygonId: [String: MKPolygonRenderer] = [:]
    private var masksByPolygonId: [String: MapKitMaskHandle] = [:]

    init(mapView: MKMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createPolygon(state: PolygonState) async -> MKPolygon? {
        guard let mapView else { return nil }

        if state.holes.isEmpty {
            return createNativePolygon(state: state, mapView: mapView)
        } else {
            return createHolePolygon(state: state, mapView: mapView)
        }
    }

    override func updatePolygonProperties(
        polygon: MKPolygon,
        current: PolygonEntity<MKPolygon>,
        prev: PolygonEntity<MKPolygon>
    ) async -> MKPolygon? {
        guard let mapView else { return polygon }
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        if finger.points != prevFinger.points || finger.geodesic != prevFinger.geodesic || finger.holes != prevFinger.holes {
            mapView.removeOverlay(polygon)
            renderersByPolygonId.removeValue(forKey: current.state.id)
            removeMask(id: current.state.id, from: mapView)
            return await createPolygon(state: current.state)
        }

        if let renderer = renderersByPolygonId[current.state.id] {
            if finger.strokeWidth != prevFinger.strokeWidth {
                renderer.lineWidth = CGFloat(current.state.strokeWidth)
            }
            if finger.strokeColor != prevFinger.strokeColor {
                renderer.strokeColor = current.state.strokeColor
            }
            if finger.fillColor != prevFinger.fillColor {
                renderer.fillColor = current.state.holes.isEmpty ? current.state.fillColor : .clear
                masksByPolygonId[current.state.id]?.tileOverlay.renderer.update(
                    points: current.state.points,
                    holes: current.state.holes,
                    fillColor: current.state.fillColor,
                    geodesic: current.state.geodesic
                )
            }
            renderer.setNeedsDisplay()
        }

        return polygon
    }

    override func removePolygon(entity: PolygonEntity<MKPolygon>) async {
        guard let mapView, let polygon = entity.polygon else { return }
        mapView.removeOverlay(polygon)
        renderersByPolygonId.removeValue(forKey: entity.state.id)
        removeMask(id: entity.state.id, from: mapView)
    }

    func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        if let tileOverlay = overlay as? PolygonMaskMKTileOverlay {
            return MKTileOverlayRenderer(overlay: tileOverlay)
        }
        guard let polygon = overlay as? MKPolygon,
              let id = polygon.title,
              let renderer = renderersByPolygonId[id] else {
            return nil
        }
        return renderer
    }

    func unbind() {
        renderersByPolygonId.removeAll()
        if let mapView {
            masksByPolygonId.values.forEach { mapView.removeOverlay($0.tileOverlay) }
        }
        masksByPolygonId.removeAll()
        mapView = nil
    }

    // MARK: - Private

    private func createNativePolygon(state: PolygonState, mapView: MKMapView) -> MKPolygon {
        let geoPoints: [GeoPointProtocol] = state.geodesic
            ? createInterpolatePoints(state.points)
            : createLinearInterpolatePoints(state.points)
        var coordinates = geoPoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }

        let interiorPolygons: [MKPolygon] = state.holes.compactMap { holePoints in
            guard !holePoints.isEmpty else { return nil }
            var holeCoords = ensureClockwiseRing(holePoints).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            return MKPolygon(coordinates: &holeCoords, count: holeCoords.count)
        }

        let polygon = interiorPolygons.isEmpty
            ? MKPolygon(coordinates: &coordinates, count: coordinates.count)
            : MKPolygon(coordinates: &coordinates, count: coordinates.count, interiorPolygons: interiorPolygons)
        polygon.title = state.id

        let renderer = MKPolygonRenderer(polygon: polygon)
        renderer.strokeColor = state.strokeColor
        renderer.lineWidth = CGFloat(state.strokeWidth)
        renderer.fillColor = state.fillColor
        renderersByPolygonId[state.id] = renderer
        mapView.addOverlay(polygon)
        return polygon
    }

    private func createHolePolygon(state: PolygonState, mapView: MKMapView) -> MKPolygon {
        // Tile overlay provides the fill + union-of-holes rendering
        let tileRenderer = PolygonRasterTileRenderer(tileSize: 256)
        tileRenderer.update(
            points: state.points,
            holes: state.holes,
            fillColor: state.fillColor,
            geodesic: state.geodesic
        )
        let tileOverlay = PolygonMaskMKTileOverlay(renderer: tileRenderer)
        tileOverlay.tileSize = CGSize(width: 256, height: 256)
        tileOverlay.minimumZ = 0
        tileOverlay.maximumZ = 22
        tileOverlay.canReplaceMapContent = false
        mapView.addOverlay(tileOverlay, level: .aboveLabels)
        masksByPolygonId[state.id] = MapKitMaskHandle(tileOverlay: tileOverlay)

        // Native polygon provides only the outer-ring stroke (no fill, no holes)
        let geoPoints: [GeoPointProtocol] = state.geodesic
            ? createInterpolatePoints(state.points)
            : createLinearInterpolatePoints(state.points)
        var coordinates = geoPoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let polygon = MKPolygon(coordinates: &coordinates, count: coordinates.count)
        polygon.title = state.id

        let renderer = MKPolygonRenderer(polygon: polygon)
        renderer.strokeColor = state.strokeColor
        renderer.lineWidth = CGFloat(state.strokeWidth)
        renderer.fillColor = .clear
        renderersByPolygonId[state.id] = renderer
        mapView.addOverlay(polygon, level: .aboveLabels)
        return polygon
    }

    private func removeMask(id: String, from mapView: MKMapView) {
        guard let handle = masksByPolygonId.removeValue(forKey: id) else { return }
        mapView.removeOverlay(handle.tileOverlay)
    }
}

// MARK: - Helpers

private struct MapKitMaskHandle {
    let tileOverlay: PolygonMaskMKTileOverlay
}

final class PolygonMaskMKTileOverlay: MKTileOverlay {
    let renderer: PolygonRasterTileRenderer

    init(renderer: PolygonRasterTileRenderer) {
        self.renderer = renderer
        super.init(urlTemplate: nil)
    }

    override func loadTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, Error?) -> Void
    ) {
        let data = renderer.renderTile(request: TileRequest(x: path.x, y: path.y, z: path.z))
        result(data, nil)
    }
}

private extension MKTileOverlayRenderer {
    // Helper to satisfy the type checker for `renderer(for:)` — renderer is created externally.
}
