# MapKitMapDesign

`MapKitMapDesign` is a struct that represents a MapKit map style. It conforms to
`MapKitMapDesignTypeProtocol` and wraps an `MKMapType` value.

## Signature

```swift
public struct MapKitMapDesign: MapKitMapDesignTypeProtocol, Hashable {
    public let id: MKMapType

    public init(id: MKMapType)
}
```

## Static Presets

- `Standard` — Standard road map with streets, labels, and points of interest.
- `Satellite` — Satellite imagery without labels.
- `Hybrid` — Satellite imagery overlaid with roads and labels.
- `SatelliteFlyover` — Satellite imagery with 3D flyover data where available.
- `HybridFlyover` — Hybrid style with 3D flyover data where available.
- `MutedStandard` — Muted (de-emphasized) standard map style.

## Methods

### `getValue()`

Returns the underlying `MKMapType` value.

```swift
public func getValue() -> MKMapType
```

### `Create(id:)`

Creates a `MapKitMapDesign` from an `MKMapType` value.

```swift
public static func Create(id: MKMapType) -> MapKitMapDesign
```

### `toMapDesignType(id:)`

Creates a value conforming to `MapKitMapDesignType` from an `MKMapType`.

```swift
public static func toMapDesignType(id: MKMapType) -> MapKitMapDesignType
```

## Example

```swift
mapState.mapDesignType = MapKitMapDesign.Hybrid

let satellite = MapKitMapDesign.Create(id: .satellite)
mapState.mapDesignType = satellite
```

---

# MapKitMapDesignType

A type alias for `any MapKitMapDesignTypeProtocol`.

## Signature

```swift
public typealias MapKitMapDesignType = any MapKitMapDesignTypeProtocol
```

---

# MapKitMapDesignTypeProtocol

A protocol extending `MapDesignTypeProtocol` with `Identifier == MKMapType`.

## Signature

```swift
public protocol MapKitMapDesignTypeProtocol: MapDesignTypeProtocol
    where Identifier == MKMapType {}
```
