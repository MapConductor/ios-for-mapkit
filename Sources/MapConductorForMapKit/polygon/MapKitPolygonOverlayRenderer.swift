import MapKit
import MapConductorCore
import UIKit

/// MapKit は穴（inner rings）をネイティブに描画できるため、ラスタタイルマスクは使わない
/// （android-for-googlemaps / ios-for-googlemaps が `Polygon.holes` を使うのと同じ方針）。
///
/// ただし `MKPolygon` は座標も `interiorPolygons` も生成後に変更できない。そのため
/// `MKPolygon` + `MKPolygonRenderer` の組み合わせだと、穴が変わるたびにオーバーレイを
/// remove → add し直すことになり、頂点ドラッグ中は毎フレームそれが走って**ちらつく**。
///
/// そこで描画は ``MapKitPolygonPathRenderer``（`MKOverlayPathRenderer` のサブクラス）に任せ、
/// `MKPolygon` は「オーバーレイの identity と `boundingMapRect`」を担うだけにしている。
/// 穴だけが変わったときはレンダラのパスを差し替えて再描画するので、オーバーレイの
/// 付け外しは起きない。外周が変わったときは `boundingMapRect` も変わるため作り直す。
@MainActor
final class MapKitPolygonOverlayRenderer: AbstractPolygonOverlayRenderer<MKPolygon> {
    private weak var mapView: MKMapView?
    private var renderersByPolygonId: [String: MapKitPolygonPathRenderer] = [:]

    init(mapView: MKMapView?) {
        self.mapView = mapView
        super.init()
    }

    /// 複数の穴が重なっている場合は結合（union）して重複を解消する。
    /// 他プロバイダ（ArcGIS/Mapbox/MapLibre/HERE/Google）と同じ `unionHoles()` を用いる。
    ///
    /// コンポーネント層（`Polygon`）のユニオンは state 1 インスタンスにつき 1 回きりで、
    /// 頂点ドラッグ後の `state.holes` 差し替えには追従しないため、ジオメトリを組み立てる
    /// ここでも結合する。
    private func resolveHoles(_ state: PolygonState) -> PolygonState {
        state.holes.count > 1 ? state.unionHoles() : state
    }

    override func createPolygon(state: PolygonState) async -> MKPolygon? {
        guard let mapView else { return nil }
        let resolved = resolveHoles(state)
        let rings = self.rings(for: resolved)
        guard var outer = rings.first, outer.count >= 3 else { return nil }

        let polygon = MKPolygon(coordinates: &outer, count: outer.count)
        polygon.title = resolved.id

        let renderer = MapKitPolygonPathRenderer(overlay: polygon)
        renderer.strokeColor = resolved.strokeColor
        renderer.lineWidth = CGFloat(resolved.strokeWidth)
        renderer.fillColor = resolved.fillColor
        renderer.update(rings: rings)
        renderersByPolygonId[resolved.id] = renderer
        mapView.addOverlay(polygon)
        return polygon
    }

    override func updatePolygonProperties(
        polygon: MKPolygon,
        current: PolygonEntity<MKPolygon>,
        prev: PolygonEntity<MKPolygon>
    ) async -> MKPolygon? {
        guard let mapView else { return polygon }
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        guard let renderer = renderersByPolygonId[current.state.id] else {
            mapView.removeOverlay(polygon)
            return await createPolygon(state: current.state)
        }

        // 外周が変わると `MKPolygon.boundingMapRect` も変わる。これは生成後に変更できず、
        // MapKit は追加時の値でクリップするため、この場合だけオーバーレイを作り直す。
        if finger.points != prevFinger.points || finger.geodesic != prevFinger.geodesic {
            mapView.removeOverlay(polygon)
            renderersByPolygonId.removeValue(forKey: current.state.id)
            return await createPolygon(state: current.state)
        }

        // 穴だけの変更（頂点ドラッグ）はパスの差し替えで済ませる。オーバーレイを付け外し
        // しないので、ドラッグ中もちらつかない。
        if finger.holes != prevFinger.holes {
            renderer.update(rings: rings(for: resolveHoles(current.state)))
        }

        if finger.strokeWidth != prevFinger.strokeWidth {
            renderer.lineWidth = CGFloat(current.state.strokeWidth)
        }
        if finger.strokeColor != prevFinger.strokeColor {
            renderer.strokeColor = current.state.strokeColor
        }
        if finger.fillColor != prevFinger.fillColor {
            renderer.fillColor = current.state.fillColor
        }
        renderer.setNeedsDisplay()

        return polygon
    }

    override func removePolygon(entity: PolygonEntity<MKPolygon>) async {
        guard let mapView, let polygon = entity.polygon else { return }
        mapView.removeOverlay(polygon)
        renderersByPolygonId.removeValue(forKey: entity.state.id)
    }

    func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        guard let polygon = overlay as? MKPolygon,
              let id = polygon.title,
              let renderer = renderersByPolygonId[id] else {
            return nil
        }
        return renderer
    }

    func unbind() {
        renderersByPolygonId.removeAll()
        mapView = nil
    }

    // MARK: - Private

    /// 描画に使うリング列。先頭が外周、以降が穴。
    private func rings(for state: PolygonState) -> [[CLLocationCoordinate2D]] {
        var result: [[CLLocationCoordinate2D]] = []
        let outer = ring(state.points, geodesic: state.geodesic)
        guard outer.count >= 3 else { return result }
        result.append(outer)
        for hole in state.holes {
            let holeRing = ring(hole, geodesic: state.geodesic)
            if holeRing.count >= 3 { result.append(holeRing) }
        }
        return result
    }

    /// リングをコア共通の補間（geodesic は球面補間・非 geodesic は線形補間）で密度化して
    /// `CLLocationCoordinate2D` へ変換する。外周・穴の両方に同じ処理を通す。
    private func ring(_ points: [GeoPointProtocol], geodesic: Bool) -> [CLLocationCoordinate2D] {
        let geoPoints: [GeoPointProtocol] = geodesic
            ? WGS84Geodesic.createInterpolatePoints(points)
            : Planar.createInterpolatePoints(points)
        return geoPoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}

// MARK: - Path renderer

/// 外周 + 穴を 1 本の `CGPath` として描く `MKOverlayPathRenderer`。
///
/// `MKPolygonRenderer` と違いジオメトリを後から差し替えられるので、穴が変わっても
/// オーバーレイを作り直さずに済む（`invalidatePath()` + `setNeedsDisplay()` だけ）。
///
/// 塗りは偶奇規則（even-odd）。穴は ``MapKitPolygonOverlayRenderer`` 側で結合済みなので
/// 穴同士が重なることはなく、リングの巻き方向にも依存しない。
final class MapKitPolygonPathRenderer: MKOverlayPathRenderer {
    /// 先頭が外周、以降が穴。MapKit の描画スレッドと MainActor の両方から触るのでロックで守る。
    private var rings: [[CLLocationCoordinate2D]] = []
    private let lock = NSLock()

    func update(rings: [[CLLocationCoordinate2D]]) {
        lock.lock()
        self.rings = rings
        lock.unlock()
        invalidatePath()
        setNeedsDisplay()
    }

    override func createPath() {
        lock.lock()
        let rings = self.rings
        lock.unlock()

        let path = CGMutablePath()
        for ring in rings where ring.count >= 3 {
            path.addLines(between: ring.map { point(for: MKMapPoint($0)) })
            path.closeSubpath()
        }
        self.path = path
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let path else { return }

        if fillColor != nil {
            context.addPath(path)
            applyFillProperties(to: context, atZoomScale: zoomScale)
            // 既定の実装は非ゼロ回転数で塗るため、リングの巻き方向によっては穴が抜けない。
            // 偶奇規則を明示して、巻き方向に依存せず穴を抜く。
            context.fillPath(using: .evenOdd)
        }
        if strokeColor != nil, lineWidth > 0 {
            context.addPath(path)
            applyStrokeProperties(to: context, atZoomScale: zoomScale)
            context.strokePath()
        }
    }
}
