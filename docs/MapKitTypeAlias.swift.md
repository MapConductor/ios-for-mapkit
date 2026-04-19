# MapKitTypeAlias

Type aliases that map MapKit SDK concrete types to the generic names used by the SDK's overlay
system.

## Aliases

- `MapKitActualMarker`
    - Type: `MKPointAnnotation`
    - Description: The MapKit annotation type used internally by the marker controller and
      renderer.
- `MapKitActualPolyline`
    - Type: `MKPolyline`
    - Description: The MapKit overlay type used for polyline rendering.
- `MapKitActualCircle`
    - Type: `MKCircle`
    - Description: The MapKit overlay type used for circle rendering.
- `MapKitActualPolygon`
    - Type: `MKPolygon`
    - Description: The MapKit overlay type used for polygon rendering.

## Signature

```swift
public typealias MapKitActualMarker   = MKPointAnnotation
public typealias MapKitActualPolyline = MKPolyline
public typealias MapKitActualCircle   = MKCircle
public typealias MapKitActualPolygon  = MKPolygon
```
