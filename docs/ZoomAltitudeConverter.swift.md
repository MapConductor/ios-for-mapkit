# MapKitZoomAltitudeConverter

Converts between Google-style zoom levels and the altitude-based camera model used by MapKit.
Implements `ZoomAltitudeConverterProtocol`.

MapKit uses `MKMapCamera(lookingAtCenter:fromDistance:pitch:heading:)` for tilt-aware
altitude conversion, matching the behavior of the other SDK integrations.

## Signature

```swift
public class MapKitZoomAltitudeConverter: ZoomAltitudeConverterProtocol {
    public let zoom0Altitude: Double

    public init(zoom0Altitude: Double = 171_319_879.0)
}
```

## Constructor Parameters

- `zoom0Altitude`
    - Type: `Double`
    - Default: `171_319_879.0`
    - Description: The reference altitude (in meters) at zoom level 0 near the equator.

## Methods

### `zoomLevelToAltitude(zoomLevel:latitude:tilt:)`

Converts a zoom level to an altitude in meters.

```swift
public func zoomLevelToAltitude(
    zoomLevel: Double,
    latitude: Double,
    tilt: Double
) -> Double
```

**Parameters**

- `zoomLevel`
    - Type: `Double`
    - Description: The map zoom level. Clamped to `[0, 22]`.
- `latitude`
    - Type: `Double`
    - Description: The camera's latitude in degrees. Clamped to `[-85, 85]`.
- `tilt`
    - Type: `Double`
    - Description: The camera tilt angle in degrees. Clamped to `[0, 90]`.

**Returns**

- Type: `Double`
- Description: The estimated altitude in meters. Clamped to `[100, 50_000_000]`.

---

### `altitudeToZoomLevel(altitude:latitude:tilt:)`

Converts an altitude in meters to a zoom level.

```swift
public func altitudeToZoomLevel(
    altitude: Double,
    latitude: Double,
    tilt: Double
) -> Double
```

**Returns**

- Type: `Double`
- Description: The estimated zoom level. Clamped to `[0, 22]`.

## Example

```swift
let converter = MapKitZoomAltitudeConverter()
let altitude = converter.zoomLevelToAltitude(zoomLevel: 14, latitude: 35.0, tilt: 0)
let zoom = converter.altitudeToZoomLevel(altitude: altitude, latitude: 35.0, tilt: 0)
// zoom ≈ 14.0
```
