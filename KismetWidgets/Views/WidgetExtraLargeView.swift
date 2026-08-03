import MapKit
import SwiftUI
import UIKit
import WidgetKit

/// Kept for coordinate helper used by map snapshot code.
extension WidgetAppGroup.Card {
	var coordinate: CLLocationCoordinate2D? {
		guard let latitude, let longitude else { return nil }
		return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
	}
}
