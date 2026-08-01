import CoreLocation
import MapKit
import MapConductorCore
import UIKit

@MainActor
final class MapKitCircleOverlayRenderer: AbstractCircleOverlayRenderer<MKPolygon> {
    private weak var mapView: MKMapView?
    /// 円 1 つにつき、±180 分割後の全断片ポリゴン（先頭がエンティティ）。
    private var fragmentsByCircleId: [String: [MKPolygon]] = [:]
    /// MKPolygonRenderer はポリゴンインスタンスに紐づくため、断片ごとに保持する。
    private var renderersByPolygon: [ObjectIdentifier: MKPolygonRenderer] = [:]

    init(mapView: MKMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createCircle(state: CircleState) async -> MKPolygon? {
        guard let mapView else { return nil }
        let fragments = makeCircleFragments(
            center: state.center,
            radiusMeters: state.radiusMeters,
            geodesic: state.geodesic
        )
        guard !fragments.isEmpty else { return nil }

        var polygons: [MKPolygon] = []
        for points in fragments {
            let polygon = MKPolygon(coordinates: points, count: points.count)
            polygon.title = state.id

            let renderer = MKPolygonRenderer(polygon: polygon)
            renderer.strokeColor = state.strokeColor
            renderer.lineWidth = CGFloat(state.strokeWidth)
            renderer.fillColor = state.fillColor

            renderersByPolygon[ObjectIdentifier(polygon)] = renderer
            mapView.addOverlay(polygon)
            polygons.append(polygon)
        }
        fragmentsByCircleId[state.id] = polygons
        return polygons[0]
    }

    override func updateCircleProperties(
        circle: MKPolygon,
        current: CircleEntity<MKPolygon>,
        prev: CircleEntity<MKPolygon>
    ) async -> MKPolygon? {
        guard mapView != nil else { return circle }
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        // If center, radius, or geodesic changed, we need to recreate the polygons
        let needsRecreation =
            finger.center != prevFinger.center ||
            finger.radiusMeters != prevFinger.radiusMeters ||
            finger.geodesic != prevFinger.geodesic

        if needsRecreation {
            removeFragments(circleId: current.state.id)
            return await createCircle(state: current.state)
        }

        // Update renderer properties on every fragment
        for polygon in fragmentsByCircleId[current.state.id] ?? [] {
            guard let renderer = renderersByPolygon[ObjectIdentifier(polygon)] else { continue }
            if finger.strokeColor != prevFinger.strokeColor {
                renderer.strokeColor = current.state.strokeColor
            }
            if finger.strokeWidth != prevFinger.strokeWidth {
                renderer.lineWidth = CGFloat(current.state.strokeWidth)
            }
            if finger.fillColor != prevFinger.fillColor {
                renderer.fillColor = current.state.fillColor
            }
            // Request redraw
            renderer.setNeedsDisplay()
        }

        return circle
    }

    override func removeCircle(entity: CircleEntity<MKPolygon>) async {
        removeFragments(circleId: entity.state.id)
    }

    func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        guard let polygon = overlay as? MKPolygon,
              let renderer = renderersByPolygon[ObjectIdentifier(polygon)] else {
            return nil
        }
        return renderer
    }

    func unbind() {
        fragmentsByCircleId.removeAll()
        renderersByPolygon.removeAll()
        mapView = nil
    }

    private func removeFragments(circleId: String) {
        for polygon in fragmentsByCircleId[circleId] ?? [] {
            mapView?.removeOverlay(polygon)
            renderersByPolygon.removeValue(forKey: ObjectIdentifier(polygon))
        }
        fragmentsByCircleId.removeValue(forKey: circleId)
    }
}

/// コア共通の `circleToRing` からリングを生成する。MapKit は経度 ±180 の単一世界で
/// 描画する（unwrap 経度は子午線へクランプされ半円になる）ため、正規化してから
/// `splitRingByMeridian` で分割し、閉じた断片ごとに MKPolygon を作る。
private func makeCircleFragments(
    center: GeoPointProtocol,
    radiusMeters: Double,
    geodesic: Bool
) -> [[CLLocationCoordinate2D]] {
    let normalized = circleToRing(center: center, radiusMeters: radiusMeters, geodesic: geodesic)
        .map { $0.normalize() }
    return splitRingByMeridian(normalized, geodesic: geodesic)
        .filter { $0.count >= 3 }
        .map { fragment in
            closeRing(fragment).map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
        }
}
