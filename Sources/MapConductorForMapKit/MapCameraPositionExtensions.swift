import Foundation
import MapKit
import MapConductorCore

private let converter = MapKitZoomAltitudeConverter(zoom0Altitude: 171_319_879.0)
private let mapKitMaxPitch: Double = 80.9
private let mapConductorTileSizePoints: Double = 256.0
private let minCosLat: Double = 0.01
private let minCosTilt: Double = 0.05

// Convert from MapCameraPosition to MKMapCamera
public extension MapCameraPosition {
    /// Pass the target map view so the camera distance is derived from the view's actual
    /// projection (FOV × viewport) and stays consistent with the top-down setVisibleMapRect
    /// path. Without a view (or before layout) it falls back to the zoom0Altitude constant,
    /// which is only accurate for a specific viewport height.
    func toMKMapCamera(on mapView: MKMapView? = nil) -> MKMapCamera {
        let nativePitch = min(abs(tilt), mapKitMaxPitch)
        let pitchRadians = nativePitch * .pi / 180.0
        // Slant distance from camera to target for this zoom. MKMapCamera's fromDistance is the
        // line-of-sight distance, so keeping it constant under pitch preserves the scale at the
        // target — same behavior as Google/MapLibre/Mapbox, where zoom is unchanged by tilt.
        let distance = mapView?.cameraDistance(forZoom: zoom, latitude: position.latitude)
            ?? converter.zoomLevelToAltitude(
                zoomLevel: zoom,
                latitude: position.latitude,
                tilt: 0.0
            )
        let target = tilt < 0.0
            ? Spherical.computeOffset(
                origin: position,
                distance: distance * tan(pitchRadians),
                heading: bearing
            )
            : position

        NSLog("MapKit (in)position=\(position),(in)tilt=\(tilt), (out)lookingAtCenter=\(target), (out)fromDistance=\(distance), (out)pitch=\(nativePitch)")
        return MKMapCamera(
            lookingAtCenter: CLLocationCoordinate2D(
                latitude: target.latitude,
                longitude: target.longitude
            ),
            fromDistance: distance,
            pitch: nativePitch,
            heading: bearing
        )
    }
}

// Convert from MKMapView to MapCameraPosition
public extension MKMapView {
    func toMapCameraPosition(
        logicalTiltHint: Double? = nil,
        visibleRegion: VisibleRegion? = nil
    ) -> MapCameraPosition {
        let cameraAltitude = camera.altitude
        let pitchRadians = camera.pitch * .pi / 180.0
        // Recover the slant distance set via MKMapCamera(fromDistance:) — the inverse of toMKMapCamera().
        let slantDistance = cameraAltitude / max(cos(pitchRadians), minCosTilt)
        var position = GeoPoint(
            latitude: camera.centerCoordinate.latitude,
            longitude: camera.centerCoordinate.longitude,
            altitude: slantDistance
        )
        var logicalTilt = camera.pitch
        let isNegativeLogicalTilt = logicalTiltHint.map { $0 < 0.0 } == true && camera.pitch > 0.0
        if isNegativeLogicalTilt {
            let recovered = Spherical.computeOffset(
                origin: position,
                distance: slantDistance * tan(pitchRadians),
                heading: camera.heading + 180.0
            )
            position = GeoPoint(
                latitude: recovered.latitude,
                longitude: recovered.longitude,
                altitude: slantDistance
            )
            logicalTilt = -camera.pitch
        }

        // Prefer the measured on-screen zoom at any pitch: it inverts exactly what
        // toMKMapCamera(on:) set via cameraDistance(forZoom:), keeping set→read roundtrips
        // stable regardless of the viewport/FOV. The converter constant is only a fallback.
        let zoom: Double
        if let visibleZoom = googleLikeZoomLevel() {
            zoom = visibleZoom
        } else {
            zoom = converter.altitudeToZoomLevel(
                altitude: cameraAltitude,
                latitude: position.latitude,
                tilt: camera.pitch
            )
        }

        return MapCameraPosition(
            position: position,
            zoom: zoom,
            bearing: camera.heading,
            tilt: logicalTilt,
            visibleRegion: visibleRegion
        )
    }
}

extension MKMapView {
    /// Camera distance (MKMapCamera fromDistance) that renders the given Web-Mercator zoom
    /// on this view. Derived from the measured projection, so it matches Google's zoom scale
    /// on any viewport and is the exact inverse of googleLikeZoomLevel().
    func cameraDistance(forZoom zoom: Double, latitude: Double) -> Double? {
        guard let factor = metersPerPointPerDistance() else { return nil }
        let clampedLat = max(-85.0, min(latitude, 85.0))
        let latitudeRadians = clampedLat * .pi / 180.0
        let cosLat = max(abs(cos(latitudeRadians)), minCosLat)
        let clampedZoom = max(0.0, min(zoom, 22.0))
        let metersPerPoint = (Earth.circumferenceMeters * cosLat) / (mapConductorTileSizePoints * pow(2.0, clampedZoom))
        let distance = metersPerPoint / factor
        guard distance.isFinite, distance > 0 else { return nil }
        return distance
    }
}

private extension MKMapView {
    /// Ground meters per screen point at the view center, measured via the current projection.
    /// Valid at any pitch: the screen-horizontal direction at the center has no perspective
    /// foreshortening, so the value always reflects the scale at the camera target.
    func measuredMetersPerPointAtCenter() -> Double? {
        guard !bounds.isEmpty else { return nil }
        let widthPoints = Double(bounds.width)
        guard widthPoints > 0 else { return nil }

        // Use map points to avoid great-circle distance (CLLocation.distance), so this matches Web Mercator scaling.
        let midY = bounds.midY
        let leftCoordinate = convert(CGPoint(x: 0, y: midY), toCoordinateFrom: self)
        let rightCoordinate = convert(CGPoint(x: bounds.maxX, y: midY), toCoordinateFrom: self)

        let leftMapPoint = MKMapPoint(leftCoordinate)
        let rightMapPoint = MKMapPoint(rightCoordinate)
        let deltaMapPoints = hypot(rightMapPoint.x - leftMapPoint.x, rightMapPoint.y - leftMapPoint.y)
        guard deltaMapPoints > 0 else { return nil }

        let centerLat = max(-85.0, min(camera.centerCoordinate.latitude, 85.0))
        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(centerLat)
        guard pointsPerMeter > 0 else { return nil }
        let metersSpan = deltaMapPoints / pointsPerMeter
        guard metersSpan > 0 else { return nil }

        let metersPerPoint = metersSpan / widthPoints
        guard metersPerPoint.isFinite, metersPerPoint > 0 else { return nil }
        return metersPerPoint
    }

    /// Ground meters per screen point per meter of camera distance. Depends only on MapKit's
    /// fixed FOV and the viewport size — not on the current camera — so it can be measured
    /// from whatever camera happens to be set and reused to place the next one.
    func metersPerPointPerDistance() -> Double? {
        guard let metersPerPoint = measuredMetersPerPointAtCenter() else { return nil }
        let pitchRadians = camera.pitch * .pi / 180.0
        let slantDistance = camera.altitude / max(cos(pitchRadians), minCosTilt)
        guard slantDistance > 0 else { return nil }
        let factor = metersPerPoint / slantDistance
        guard factor.isFinite, factor > 0 else { return nil }
        return factor
    }

    func googleLikeZoomLevel() -> Double? {
        guard let metersPerPoint = measuredMetersPerPointAtCenter() else { return nil }
        let centerLat = max(-85.0, min(camera.centerCoordinate.latitude, 85.0))
        let latitudeRadians = centerLat * .pi / 180.0
        let cosLat = max(abs(cos(latitudeRadians)), minCosLat)

        let zoom = log2((Earth.circumferenceMeters * cosLat) / (mapConductorTileSizePoints * metersPerPoint))
        guard zoom.isFinite else { return nil }
        return max(0.0, min(zoom, 22.0))
    }
}
