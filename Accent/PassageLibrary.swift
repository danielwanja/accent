import Foundation

struct LibraryPassage: Identifiable {
    let id: String
    let title: String
    let focus: String   // which French → English issue it targets
    let text: String
}

/// Curated passages, each saturated with one issue from the French-speaker map.
enum PassageLibrary {
    static let curated: [LibraryPassage] = [
        LibraryPassage(
            id: "th",
            title: "Three Brothers",
            focus: "TH — /θ/ and /ð/",
            text: "I think these three brothers live near the theater. Together they gather every Thursday, whether the weather is worth the trip or not."),
        LibraryPassage(
            id: "h",
            title: "The Hidden Harbor",
            focus: "H — dropped and hypercorrected",
            text: "Henry hid his heavy hat behind the hotel. How he hoped the harbor air would help his aching head."),
        LibraryPassage(
            id: "vowels",
            title: "Ship or Sheep",
            focus: "Vowels — /ɪ/ vs /iː/",
            text: "Please sit in this seat and eat the chips. Did you feel the heat when the ship began to slip into the deep green sea?"),
        LibraryPassage(
            id: "stress",
            title: "Development",
            focus: "Stress — the moving target",
            text: "The development of a comfortable vocabulary is necessary. Photography, biology, and technology carry their stress in surprising places."),
    ]
}
