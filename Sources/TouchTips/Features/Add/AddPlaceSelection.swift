/// A late location suggestion must preserve the user's choice, including "No place".
struct AddPlaceSelection {
    private(set) var chosen: PlaceChoice?
    private var hasUserChoice = false

    mutating func choose(_ place: PlaceChoice?) {
        hasUserChoice = true
        chosen = place
    }

    mutating func suggest(_ place: PlaceChoice?) {
        guard !hasUserChoice else { return }
        chosen = place
    }
}
