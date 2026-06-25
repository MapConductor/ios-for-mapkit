import Foundation
import CoreLocation
import MapKit
import MapConductorCore
import QuartzCore
import UIKit

final class MapKitViewController: MapViewControllerProtocol {
    let holder: AnyMapViewHolder
    let coroutine = CoroutineScope()
    private weak var mapView: MKMapView?
    private let tileSizePoints: Double = 256.0
    private let minCosLat: Double = 0.01

    private var cameraAnimationDisplayLink: CADisplayLink?
    private var cameraAnimationFrames: [MapCameraPosition] = []
    private var cameraAnimationStartTime: CFTimeInterval = 0
    private var cameraAnimationDurationSeconds: Double = 0
    private var cameraAnimationLastIndex: Int = -1

    private var cameraMoveStartListener: OnCameraMoveHandler?
    private var cameraMoveListener: OnCameraMoveHandler?
    private var cameraMoveEndListener: OnCameraMoveHandler?
    private var mapClickListener: OnMapEventHandler?
    private var mapLongClickListener: OnMapEventHandler?
    private var mapInitializedListener: OnMapInitializedHandler?

    init(mapView: MKMapView) {
        self.mapView = mapView
        self.holder = AnyMapViewHolder(MapKitViewHolder(mapView: mapView))
    }

    deinit {
        cancelCameraAnimation()
    }

    func clearOverlays() async {
        guard let mapView = mapView else { return }
        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)
    }

    func setCameraMoveStartListener(listener: OnCameraMoveHandler?) {
        cameraMoveStartListener = listener
    }

    func setCameraMoveListener(listener: OnCameraMoveHandler?) {
        cameraMoveListener = listener
    }

    func setCameraMoveEndListener(listener: OnCameraMoveHandler?) {
        cameraMoveEndListener = listener
    }

    func setMapClickListener(listener: OnMapEventHandler?) {
        mapClickListener = listener
    }

    func setMapLongClickListener(listener: OnMapEventHandler?) {
        mapLongClickListener = listener
    }

    func setMapInitializedListener(listener: OnMapInitializedHandler?) {
        mapInitializedListener = listener
    }

    func moveCamera(position: MapCameraPosition) {
        cancelCameraAnimation()
        guard let mapView = mapView else { return }
        if abs(position.tilt) < 0.01, mapView.bounds.isEmpty {
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                _ = self.applyTopDownZoom(position: position, mapView: mapView, animated: false)
            }
        }
        if applyTopDownZoom(position: position, mapView: mapView, animated: false) {
            return
        }
        let camera = position.toMKMapCamera()
        mapView.setCamera(camera, animated: false)
    }

    func animateCamera(position: MapCameraPosition, duration: Long) {
        cancelCameraAnimation()
        guard let mapView = mapView else { return }
        let durationSeconds = Double(duration) / 1000.0
        guard durationSeconds > 0 else {
            moveCamera(position: position)
            return
        }

        let from = mapView.toMapCameraPosition()
        cameraAnimationFrames = makeCameraAnimationFrames(from: from, to: position, durationSeconds: durationSeconds)
        cameraAnimationStartTime = CACurrentMediaTime()
        cameraAnimationDurationSeconds = durationSeconds
        cameraAnimationLastIndex = -1

        let displayLink = CADisplayLink(target: self, selector: #selector(onCameraAnimationTick(_:)))
        displayLink.add(to: .main, forMode: .common)
        cameraAnimationDisplayLink = displayLink
    }

    func fitBounds(bounds: GeoRectBounds, padding: Int) {
        guard let mapView = mapView,
              let sw = bounds.southWest,
              let ne = bounds.northEast else { return }
        let swPoint = MKMapPoint(CLLocationCoordinate2D(latitude: sw.latitude, longitude: sw.longitude))
        let nePoint = MKMapPoint(CLLocationCoordinate2D(latitude: ne.latitude, longitude: ne.longitude))
        let rect = MKMapRect(
            x: min(swPoint.x, nePoint.x),
            y: min(nePoint.y, swPoint.y),
            width: abs(nePoint.x - swPoint.x),
            height: abs(swPoint.y - nePoint.y)
        )
        let edgePadding = UIEdgeInsets(top: CGFloat(padding), left: CGFloat(padding), bottom: CGFloat(padding), right: CGFloat(padding))
        mapView.setVisibleMapRect(rect, edgePadding: edgePadding, animated: false)
    }

    func notifyCameraMoveStart(_ cameraPosition: MapCameraPosition) {
        cameraMoveStartListener?(cameraPosition)
    }

    func notifyCameraMove(_ cameraPosition: MapCameraPosition) {
        cameraMoveListener?(cameraPosition)
    }

    func notifyCameraMoveEnd(_ cameraPosition: MapCameraPosition) {
        cameraMoveEndListener?(cameraPosition)
    }

    func notifyMapClick(_ point: GeoPoint) {
        mapClickListener?(point)
    }

    func notifyMapLongClick(_ point: GeoPoint) {
        mapLongClickListener?(point)
    }

    func notifyMapInitialized() {
        mapInitializedListener?(.MapCreated)
    }

    private func applyTopDownZoom(position: MapCameraPosition, mapView: MKMapView, animated: Bool, duration: Double = 0.0) -> Bool {
        // For top-down cameras, setVisibleMapRect can match Google/WebMercator zoom precisely (including latitude scaling)
        // based on the viewport size. This avoids relying on a single magic constant (zoom0Altitude) for MapKit.
        let isTopDown = abs(position.tilt) < 0.01
        guard isTopDown, !mapView.bounds.isEmpty else { return false }
        // At very low zoom levels, MapKit's map rect handling can "wrap" in a way that ends up showing
        // the world centered near the Pacific. Prefer the altitude-based camera conversion in that case.
        guard position.zoom >= 3.0 else { return false }

        let widthPoints = Double(mapView.bounds.width)
        let heightPoints = Double(mapView.bounds.height)
        guard widthPoints > 0, heightPoints > 0 else { return false }

        let centerLat = max(-85.0, min(position.position.latitude, 85.0))
        let latitudeRadians = centerLat * .pi / 180.0
        let cosLat = max(abs(cos(latitudeRadians)), minCosLat)

        let metersPerPoint = (Earth.circumferenceMeters * cosLat) / (tileSizePoints * pow(2.0, position.zoom))
        guard metersPerPoint.isFinite, metersPerPoint > 0 else { return false }

        let widthMeters = metersPerPoint * widthPoints
        let heightMeters = metersPerPoint * heightPoints

        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(centerLat)
        guard pointsPerMeter > 0 else { return false }
        let mapRectWidth = widthMeters * pointsPerMeter
        let mapRectHeight = heightMeters * pointsPerMeter
        guard mapRectWidth.isFinite, mapRectHeight.isFinite, mapRectWidth > 0, mapRectHeight > 0 else { return false }

        let centerCoordinate = CLLocationCoordinate2D(latitude: position.position.latitude, longitude: position.position.longitude)
        let centerPoint = MKMapPoint(centerCoordinate)
        // Clamp the visible rect to the MapKit world. Extremely large rects can cause MapKit
        // to "wrap" and end up centered far away from the requested coordinate.
        let world = MKMapRect.world
        // If the requested rect is close to "world size", we tend to hit MapKit edge cases.
        // Fall back to altitude-based camera conversion to keep the center stable.
        if mapRectWidth >= world.size.width * 0.98 || mapRectHeight >= world.size.height * 0.98 {
            return false
        }
        let clampedWidth = min(mapRectWidth, world.size.width)
        let clampedHeight = min(mapRectHeight, world.size.height)

        var originX = centerPoint.x - clampedWidth / 2.0
        var originY = centerPoint.y - clampedHeight / 2.0

        originX = max(world.origin.x, min(originX, world.maxX - clampedWidth))
        originY = max(world.origin.y, min(originY, world.maxY - clampedHeight))

        let rect = MKMapRect(x: originX, y: originY, width: clampedWidth, height: clampedHeight)

        // Apply heading explicitly (including 0) without changing scale.
        var camera = mapView.camera
        camera.centerCoordinate = centerCoordinate
        camera.heading = position.bearing
        camera.pitch = 0

        if animated && duration > 0 {
            // Use UIView.animate to respect the specified duration
            UIView.animate(withDuration: duration) {
                mapView.setVisibleMapRect(rect, edgePadding: .zero, animated: false)
                mapView.setCamera(camera, animated: false)
            }
        } else {
            // Use MapKit's default animation or no animation
            mapView.setVisibleMapRect(rect, edgePadding: .zero, animated: animated)
            mapView.setCamera(camera, animated: animated)
        }

        return true
    }

    private func cancelCameraAnimation() {
        cameraAnimationDisplayLink?.invalidate()
        cameraAnimationDisplayLink = nil
        cameraAnimationFrames.removeAll()
        cameraAnimationDurationSeconds = 0
        cameraAnimationStartTime = 0
        cameraAnimationLastIndex = -1
    }

    @objc private func onCameraAnimationTick(_ displayLink: CADisplayLink) {
        guard let mapView = mapView else {
            cancelCameraAnimation()
            return
        }
        guard cameraAnimationDurationSeconds > 0, !cameraAnimationFrames.isEmpty else {
            cancelCameraAnimation()
            return
        }

        let elapsed = CACurrentMediaTime() - cameraAnimationStartTime
        let progress = max(0.0, min(1.0, elapsed / cameraAnimationDurationSeconds))

        let frameCount = cameraAnimationFrames.count
        let maxIndex = frameCount - 1
        let targetIndex = min(maxIndex, Int(floor(progress * Double(maxIndex))))

        if targetIndex != cameraAnimationLastIndex {
            cameraAnimationLastIndex = targetIndex
            let frame = cameraAnimationFrames[targetIndex]
            applyCameraFrame(frame, mapView: mapView)
        }

        if progress >= 1.0 {
            cancelCameraAnimation()
        }
    }

    private func applyCameraFrame(_ position: MapCameraPosition, mapView: MKMapView) {
        // One-step move (no MapKit internal animation). This is the basis for our custom duration-controlled animation.
        if applyTopDownZoom(position: position, mapView: mapView, animated: false) {
            return
        }
        let camera = position.toMKMapCamera()
        mapView.setCamera(camera, animated: false)
    }

    private func makeCameraAnimationFrames(from: MapCameraPosition, to: MapCameraPosition, durationSeconds: Double) -> [MapCameraPosition] {
        let fps = 60.0
        let frameCount = max(2, Int(ceil(durationSeconds * fps)) + 1)
        var frames: [MapCameraPosition] = []
        frames.reserveCapacity(frameCount)

        for idx in 0..<frameCount {
            let t = Double(idx) / Double(frameCount - 1)
            frames.append(interpolateCamera(from: from, to: to, t: t))
        }
        return frames
    }

    private func interpolateCamera(from: MapCameraPosition, to: MapCameraPosition, t: Double) -> MapCameraPosition {
        let position = GeoPoint(
            latitude: lerp(from.position.latitude, to.position.latitude, t),
            longitude: interpolateLongitude(from: from.position.longitude, to: to.position.longitude, t),
            altitude: 0
        )

        let zoom = lerp(from.zoom, to.zoom, t)
        let bearing = interpolateAngleDegrees(from: from.bearing, to: to.bearing, t)
        let tilt = lerp(from.tilt, to.tilt, t)

        return MapCameraPosition(
            position: position,
            zoom: zoom,
            bearing: bearing,
            tilt: tilt,
            paddings: to.paddings,
            visibleRegion: nil
        )
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private func interpolateLongitude(from: Double, to: Double, _ t: Double) -> Double {
        var delta = to - from
        while delta > 180.0 { delta -= 360.0 }
        while delta < -180.0 { delta += 360.0 }
        return normalizeLongitude(from + delta * t)
    }

    private func normalizeLongitude(_ lng: Double) -> Double {
        (((lng + 180.0).truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)) - 180.0
    }

    private func interpolateAngleDegrees(from: Double, to: Double, _ t: Double) -> Double {
        var delta = to - from
        delta = ((delta + 540.0).truncatingRemainder(dividingBy: 360.0)) - 180.0
        let value = from + delta * t
        return (value.truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
    }
}
