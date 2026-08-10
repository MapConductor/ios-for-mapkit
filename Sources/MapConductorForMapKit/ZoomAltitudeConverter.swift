import Foundation
import MapConductorCore

/// 統一ズーム（Google Maps 基準・256px タイル）⇄ 高度の変換。
///
/// MapKit はズームレベルではなくカメラ高度（`MKMapCamera.altitude`）で縮尺を決める。
/// `MKMapCamera(…fromDistance:)` が受けるのは斜距離なので、
/// `altitude = distance * cos(tilt)` の関係で結び付けている。オフセットは 0。
/// 換算式はコアの ``WebMercatorZoomAltitudeConverter`` にある。
public class MapKitZoomAltitudeConverter: WebMercatorZoomAltitudeConverter {
    public init(zoom0Altitude: Double = AbstractZoomAltitudeConverter.defaultZoom0Altitude) {
        super.init(zoom0Altitude: zoom0Altitude, zoomOffset: 0.0)
    }
}
