import Foundation

class DataLoader {
    static func load<T: Decodable>(filename: String, as type: T.Type) -> T? {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            print("[DataLoader] Missing resource: \(filename).json in bundle")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: data)
        } catch {
            print("[DataLoader] Error decoding \(filename).json: \(error)")
            return nil
        }
    }
}
