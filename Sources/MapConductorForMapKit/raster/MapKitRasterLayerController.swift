import MapKit
import MapConductorCore

@MainActor
final class MapKitRasterLayerController: RasterLayerController<MKTileOverlay, MapKitRasterLayerOverlayRenderer> {
    private weak var mapView: MKMapView?

    init(mapView: MKMapView?) {
        self.mapView = mapView
        let rasterManager = RasterLayerManager<MKTileOverlay>()
        let renderer = MapKitRasterLayerOverlayRenderer(mapView: mapView)
        super.init(rasterLayerManager: rasterManager, renderer: renderer)
    }

    func unbind() {
        mapView = nil
        destroy()
    }
}
