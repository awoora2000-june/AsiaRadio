import CoreLocation
import Foundation

enum ChannelStationSorting {
    static func sortedByDistance(_ stations: [RadioStation], userLocation: CLLocation?) -> [RadioStation] {
        guard let userLocation else { return stations }
        return stations.sorted { lhs, rhs in
            compareByDistance(lhs: lhs, rhs: rhs, from: userLocation)
        }
    }

    private static func compareByDistance(lhs: RadioStation, rhs: RadioStation, from location: CLLocation) -> Bool {
        let left = lhs.distanceMeters(from: location)
        let right = rhs.distanceMeters(from: location)

        switch (left, right) {
        case let (l?, r?):
            if l != r { return l < r }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

enum CountrySorting {
    static func sortedByDistance(
        _ countries: [RadioCountry] = Array(RadioCountry.allCases),
        userLocation: CLLocation?
    ) -> [RadioCountry] {
        guard let userLocation else { return countries }
        return countries.sorted { lhs, rhs in
            let left = lhs.distanceMeters(from: userLocation)
            let right = rhs.distanceMeters(from: userLocation)
            if left != right { return left < right }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}

extension RadioCountry {
    func distanceMeters(from location: CLLocation) -> Double {
        let coordinate = approximateCoordinate
        let countryLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location.distance(from: countryLocation)
    }
}

extension RadioStation {
    func distanceMeters(from location: CLLocation) -> Double? {
        guard let geoLat, let geoLong else { return nil }
        let stationLocation = CLLocation(latitude: geoLat, longitude: geoLong)
        return location.distance(from: stationLocation)
    }
}
