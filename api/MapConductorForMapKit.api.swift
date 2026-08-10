import Combine
import CoreGraphics
import CoreLocation
import Foundation
import MapConductorCore
import MapKit
import QuartzCore
import Swift
import SwiftUI
import UIKit
import _Concurrency
import _MapKit_SwiftUI
import _StringProcessing
import _SwiftConcurrencyShims
extension MapConductorCore.MapCameraPosition {
  final public func toMKMapCamera(on mapView: MapKit.MKMapView? = nil) -> MapKit.MKMapCamera
}
extension MapKit.MKMapView {
  @_Concurrency.MainActor @preconcurrency public func toMapCameraPosition(logicalTiltHint: Swift.Double? = nil, visibleRegion: MapConductorCore.VisibleRegion? = nil) -> MapConductorCore.MapCameraPosition
}
public protocol MapKitMapDesignTypeProtocol : MapConductorCore.MapDesignTypeProtocol where Self.Identifier == MapKit.MKMapType {
}
public typealias MapKitMapDesignType = any MapConductorForMapKit.MapKitMapDesignTypeProtocol
public struct MapKitMapDesign : MapConductorForMapKit.MapKitMapDesignTypeProtocol, Swift.Hashable {
  public let id: MapKit.MKMapType
  public let attributionRules: [MapConductorCore.AttributionRule]
  public init(id: MapKit.MKMapType, attributionRules: [MapConductorCore.AttributionRule] = [])
  public func getValue() -> MapKit.MKMapType
  public static let Standard: MapConductorForMapKit.MapKitMapDesign
  public static let Satellite: MapConductorForMapKit.MapKitMapDesign
  public static let Hybrid: MapConductorForMapKit.MapKitMapDesign
  public static let SatelliteFlyover: MapConductorForMapKit.MapKitMapDesign
  public static let HybridFlyover: MapConductorForMapKit.MapKitMapDesign
  public static let MutedStandard: MapConductorForMapKit.MapKitMapDesign
  public static func Create(id: MapKit.MKMapType) -> MapConductorForMapKit.MapKitMapDesign
  public static func toMapDesignType(id: MapKit.MKMapType) -> MapConductorForMapKit.MapKitMapDesignType
  public static func == (a: MapConductorForMapKit.MapKitMapDesign, b: MapConductorForMapKit.MapKitMapDesign) -> Swift.Bool
  public typealias Identifier = MapKit.MKMapType
  public func hash(into hasher: inout Swift.Hasher)
  public var hashValue: Swift.Int {
    get
  }
}
@_Concurrency.MainActor @preconcurrency public struct MapKitMapView : SwiftUICore.View {
  @_Concurrency.MainActor @preconcurrency public init(state: MapConductorForMapKit.MapKitViewState, cameraRestriction: MapConductorCore.CameraRestriction? = nil, onMapLoaded: MapConductorCore.OnMapLoadedHandler<MapConductorForMapKit.MapKitViewState>? = nil, onMapClick: MapConductorCore.OnMapEventHandler? = nil, onMapLongClick: MapConductorCore.OnMapEventHandler? = nil, onCameraMoveStart: MapConductorCore.OnCameraMoveHandler? = nil, onCameraMove: MapConductorCore.OnCameraMoveHandler? = nil, onCameraMoveEnd: MapConductorCore.OnCameraMoveHandler? = nil, sdkInitialize: (() -> Swift.Void)? = nil, @MapConductorCore.MapViewContentBuilder content: @escaping () -> MapConductorCore.MapViewContent = { MapViewContent() })
  @_Concurrency.MainActor @preconcurrency public var body: some SwiftUICore.View {
    get
  }
  public typealias Body = @_opaqueReturnTypeOf("$s015MapConductorForA3Kit0adA4ViewV4bodyQrvp", 0) __
}
public typealias MapKitActualMarker = MapKit.MKPointAnnotation
public typealias MapKitActualPolyline = MapKit.MKPolyline
public typealias MapKitActualCircle = MapKit.MKCircle
public typealias MapKitActualPolygon = MapKit.MKPolygon
final public class MapKitViewState : MapConductorCore.MapViewState<MapConductorForMapKit.MapKitMapDesignType> {
  final public var mapViewHolder: MapConductorForMapKit.MapKitViewHolder? {
    get
  }
  override final public var mapDesignType: MapConductorForMapKit.MapKitMapDesignType {
    get
    set
  }
  public init(id: Swift.String, mapDesignType: MapConductorForMapKit.MapKitMapDesignType = MapKitMapDesign.Standard, cameraPosition: MapConductorCore.MapCameraPosition = .Default, uiSettings: MapConductorCore.MapUISettings = MapUISettings())
  convenience public init(mapDesignType: MapConductorForMapKit.MapKitMapDesignType = MapKitMapDesign.Standard, cameraPosition: MapConductorCore.MapCameraPosition = .Default, uiSettings: MapConductorCore.MapUISettings = MapUISettings())
  override final public func getMapViewHolder() -> MapConductorCore.AnyMapViewHolder?
  @objc deinit
}
public class MapKitZoomAltitudeConverter : MapConductorCore.WebMercatorZoomAltitudeConverter {
  public init(zoom0Altitude: Swift.Double = AbstractZoomAltitudeConverter.defaultZoom0Altitude)
  @objc deinit
}
@_hasMissingDesignatedInitializers final public class MapKitViewHolder : MapConductorCore.MapViewHolderProtocol {
  final public let mapView: MapKit.MKMapView
  final public let map: MapKit.MKMapView
  final public func toScreenOffset(position: any MapConductorCore.GeoPointProtocol) -> CoreFoundation.CGPoint?
  final public func fromScreenOffset(offset: CoreFoundation.CGPoint) async -> MapConductorCore.GeoPoint?
  final public func fromScreenOffsetSync(offset: CoreFoundation.CGPoint) -> MapConductorCore.GeoPoint?
  public typealias ActualMap = MapKit.MKMapView
  public typealias ActualMapView = MapKit.MKMapView
  @objc deinit
}
extension MapConductorForMapKit.MapKitMapView : Swift.Sendable {}
