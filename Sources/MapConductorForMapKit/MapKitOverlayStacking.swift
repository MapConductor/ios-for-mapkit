import Foundation
import MapKit
@_spi(MapConductorDriver) import MapConductorCore

/// オーバーレイを、重なり順の帯（``OverlayBand``）の位置へ差し込む。
///
/// 下から ラスター < グラウンドイメージ < ポリゴン < サークル < ポリライン < マーカーのタイル。
/// MapKit は同じ level の中では足した順に重ねるので、以前は後から足したもの
/// （clearOverlays の後に送り直したグラウンドイメージなど）が上に来ていた。
/// ここでは level の中の並びで帯の位置を計算して `insertOverlay(_:at:level:)` する。
///
/// ## level とラベル
///
/// `addOverlay(_:)` の既定の level は `.aboveRoads`（ラベルの下）で、ポリゴン・サークル・
/// ポリラインは以前からラベルの下にあった。一方ラスター・グラウンドイメージ・マーカーのタイルは
/// `.aboveLabels` で足していたので、**ラスターがポリゴン等より上**に描かれていた。
/// 帯の順を守るには、ラスターとグラウンドイメージをポリゴン等と同じ level に置く必要がある。
/// ここではポリゴン等のラベルとの関係を変えない方を選び、マーカーの帯以外はすべて
/// `.aboveRoads`、マーカーのタイルだけ `.aboveLabels` に置く。
/// その結果ラスター（GL 系と同じくラベルの下になる）とグラウンドイメージ（以前はラベルの上）が
/// ラベルの下へ移る。
///
/// - マーカー（`MKAnnotation`）は MapKit が常にオーバーレイより上に描くので、帯の条件を満たす。
/// - 帯の中の zIndex は足した時点の値で並べる（MapKit の描画担当は zIndex の変更を受けて
///   並べ直さない。従来から未対応）。
@MainActor
enum MapKitOverlayStacking {
    static func level(for key: OverlayStackKey) -> MKOverlayLevel {
        key.band == .marker ? .aboveLabels : .aboveRoads
    }

    static func add(_ overlay: MKOverlay, _ key: OverlayStackKey, to mapView: MKMapView) {
        let level = level(for: key)
        let registry = keys(of: mapView)
        registry.setObject(KeyBox(key), forKey: overlay)
        let existing = mapView.overlays(in: level)
        let keys = existing.map { (registry.object(forKey: $0) as KeyBox?)?.key }
        let index = OverlayStacking.insertionIndex(for: key, among: keys)
        if index >= existing.count {
            mapView.addOverlay(overlay, level: level)
        } else {
            mapView.insertOverlay(overlay, at: index, level: level)
        }
    }

    private final class KeyBox: NSObject {
        let key: OverlayStackKey
        init(_ key: OverlayStackKey) { self.key = key }
    }

    private static var registryKey: UInt8 = 0

    /// 地図ごとの「オーバーレイ → 帯のキー」。オーバーレイは弱参照で持つので、外したものは自然に消える。
    private static func keys(of mapView: MKMapView) -> NSMapTable<AnyObject, KeyBox> {
        if let table = objc_getAssociatedObject(mapView, &registryKey) as? NSMapTable<AnyObject, KeyBox> {
            return table
        }
        let table = NSMapTable<AnyObject, KeyBox>.weakToStrongObjects()
        objc_setAssociatedObject(mapView, &registryKey, table, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return table
    }
}
