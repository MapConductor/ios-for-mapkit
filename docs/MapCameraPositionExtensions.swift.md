# MapCameraPosition extension

## `toMKMapCamera()`

Converts a `MapCameraPosition` to an `MKMapCamera` for use with MapKit.

### Signature

```swift
public extension MapCameraPosition {
    func toMKMapCamera() -> MKMapCamera
}
```

### Returns

- Type: `MKMapCamera`
- Description: An `MKMapCamera` with center coordinate, altitude, pitch, and heading derived
  from the `MapCameraPosition`. Altitude is computed from zoom level using
  `MapKitZoomAltitudeConverter`.

---

# MKMapView extension

## `toMapCameraPosition(visibleRegion:)`

Converts the current `MKMapView` camera to a `MapCameraPosition`. Zoom level is derived from the
map's visible region using a Web Mercator projection via `MKMapPoints`.

### Signature

```swift
public extension MKMapView {
    func toMapCameraPosition(visibleRegion: VisibleRegion? = nil) -> MapCameraPosition
}
```

### Parameters

- `visibleRegion`
    - Type: `VisibleRegion?`
    - Default: `nil`
    - Description: The visible map region. When provided, the resulting `MapCameraPosition`
      includes accurate `visibleRegion` bounds.

### Returns

- Type: `MapCameraPosition`
- Description: A `MapCameraPosition` with position, zoom (derived via `googleLikeZoomLevel()`),
  bearing, and tilt populated from the current `MKMapView` camera.
