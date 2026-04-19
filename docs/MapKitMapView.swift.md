# MapKitMapView

A SwiftUI view that renders a MapKit map. Accepts a declarative overlay tree via
`@MapViewContentBuilder`. MapKit does not require an API key, but the view supports
`sdkInitialize` for parity with the other provider views.

## Signature

```swift
public struct MapKitMapView: View {
    public init(
        state: MapKitViewState,
        onMapLoaded: OnMapLoadedHandler<MapKitViewState>? = nil,
        onMapClick: OnMapEventHandler? = nil,
        onCameraMoveStart: OnCameraMoveHandler? = nil,
        onCameraMove: OnCameraMoveHandler? = nil,
        onCameraMoveEnd: OnCameraMoveHandler? = nil,
        sdkInitialize: (() -> Void)? = nil,
        @MapViewContentBuilder content: @escaping () -> MapViewContent = { MapViewContent() }
    )
}
```

## Parameters

- `state`
    - Type: `MapKitViewState`
    - Description: The observable state object controlling camera position and map design.
      Hold with `@StateObject` in the parent view.
- `onMapLoaded`
    - Type: `OnMapLoadedHandler<MapKitViewState>?`
    - Default: `nil`
    - Description: Called once when the map finishes loading. Receives the `MapKitViewState`.
- `onMapClick`
    - Type: `OnMapEventHandler?`
    - Default: `nil`
    - Description: Called with the tapped geographic coordinate when the user taps the map.
- `onCameraMoveStart`
    - Type: `OnCameraMoveHandler?`
    - Default: `nil`
    - Description: Called with the camera position when a camera movement begins.
- `onCameraMove`
    - Type: `OnCameraMoveHandler?`
    - Default: `nil`
    - Description: Called continuously with the current camera position during movement.
- `onCameraMoveEnd`
    - Type: `OnCameraMoveHandler?`
    - Default: `nil`
    - Description: Called with the final camera position when movement ends.
- `sdkInitialize`
    - Type: `(() -> Void)?`
    - Default: `nil`
    - Description: Optional initialization closure. It is executed once before the native
      `MKMapView` is created.
- `content`
    - Type: `@MapViewContentBuilder () -> MapViewContent`
    - Default: empty
    - Description: Declarative overlay tree. Supports `Marker`, `Polyline`, `Polygon`,
      `Circle`, `GroundImage`, `RasterLayer`, `InfoBubble`, and `ForArray`.

## Notes

- MapKit requires no API key for basic map display.
- `sdkInitialize` is still called when provided, so applications can use the same provider setup path across map SDKs.

## Example

```swift
import MapConductorForMapKit
import SwiftUI

struct MyMapScreen: View {
    @StateObject private var mapState = MapKitViewState(
        mapDesignType: MapKitMapDesign.Standard,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 13.0
        )
    )

    var body: some View {
        MapKitMapView(state: mapState)
            .ignoresSafeArea()
    }
}
```
