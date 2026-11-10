import Foundation

/// Maps everyday search words ("sunny", "party", "beach") to the labels produced by Apple's Vision classifier
/// (e.g. `blue_sky`, `celebration`). Weights express how strongly a label implies the concept.
enum SearchConcepts {
    private static let groups: [(aliases: [String], labels: [String: Float])] = [
        (["sunny", "sunshine", "sun", "bright", "clear", "summer", "daylight"],
         ["sun": 1, "blue_sky": 1, "sky": 0.8, "daytime": 0.7, "outdoor": 0.5, "sunbathing": 0.5, "beach": 0.4]),
        (["cloudy", "cloud", "clouds", "overcast", "gloomy"], ["cloudy": 1, "sky": 0.6, "haze": 0.4]),
        (["rain", "rainy", "storm", "stormy", "wet", "monsoon"],
         ["storm": 0.9, "thunderstorm": 0.9, "umbrella": 0.7, "cloudy": 0.6, "rainbow": 0.4, "water": 0.3, "lightning": 0.6]),
        (["sunset", "sunrise", "dusk", "dawn", "golden"], ["sunset_sunrise": 1, "sky": 0.4]),
        (["night", "dark", "evening", "moon", "stars", "starry"], ["night_sky": 1, "moon": 0.9, "nightclub": 0.3, "fireworks": 0.3, "celestial_body": 0.6]),
        (["beach", "sea", "ocean", "seaside", "coast", "shore", "sand", "island"],
         ["beach": 1, "ocean": 1, "shore": 0.9, "sand": 0.8, "water_body": 0.6, "island": 0.6, "surfing": 0.4, "seashell": 0.5, "sandcastle": 0.5, "sunbathing": 0.5]),
        (["water", "lake", "river", "pond", "waterfall", "stream"],
         ["water": 0.8, "water_body": 1, "lake": 1, "river": 1, "waterfall": 0.9, "creek": 0.8, "waterways": 0.8]),
        (["mountain", "mountains", "hill", "hills", "hiking", "trek", "trekking", "cliff", "valley"],
         ["mountain": 1, "hill": 0.9, "hiking": 0.8, "canyon": 0.5, "cliff": 0.6, "glacier": 0.5, "volcano": 0.6, "outdoor": 0.3]),
        (["nature", "outdoor", "outdoors", "scenery", "landscape", "scenic"],
         ["outdoor": 1, "tree": 0.7, "forest": 0.7, "grass": 0.7, "vegetation": 0.8, "foliage": 0.6, "plant": 0.5, "mountain": 0.5, "sky": 0.4, "water_body": 0.4]),
        (["forest", "jungle", "tree", "trees", "woods", "green"],
         ["forest": 1, "jungle": 0.9, "tree": 1, "foliage": 0.7, "vegetation": 0.7, "evergreen": 0.7, "palm_tree": 0.6, "grass": 0.4]),
        (["flower", "flowers", "garden", "blossom", "bloom", "floral"],
         ["flower": 1, "blossom": 0.9, "bouquet": 0.8, "garden": 0.8, "rose": 0.8, "tulip": 0.8, "sunflower": 0.8, "orchid": 0.8, "daisy": 0.8, "flower_arrangement": 0.8, "plant": 0.3]),
        (["snow", "snowy", "winter", "ice", "icy", "cold", "frozen"],
         ["snow": 1, "winter_sport": 0.7, "ice": 0.8, "blizzard": 0.8, "snowman": 0.8, "skiing": 0.7, "sledding": 0.7, "glacier": 0.7, "iceberg": 0.7, "frozen": 0.6]),
        (["food", "meal", "eat", "eating", "dinner", "lunch", "breakfast", "delicious", "yummy", "tasty", "cuisine"],
         ["food": 1, "restaurant": 0.7, "plate": 0.7, "tableware": 0.5, "dessert": 0.6, "meat": 0.5, "vegetable": 0.5, "fruit": 0.5, "pizza": 0.7, "pasta": 0.7, "rice": 0.7, "bread": 0.6, "salad": 0.6, "soup": 0.6, "sandwich": 0.6, "curry": 0.7, "burrito": 0.6, "cake": 0.4]),
        (["drink", "drinks", "beverage", "coffee", "tea", "juice", "beer", "wine", "cocktail"],
         ["drink": 1, "coffee": 1, "tea_drink": 0.9, "juice": 0.9, "beer": 0.9, "wine": 0.9, "cocktail": 0.9, "drinking_glass": 0.7, "mug": 0.6, "cup": 0.6, "smoothie": 0.8, "soda": 0.8]),
        (["dessert", "sweet", "sweets", "cake", "chocolate", "icecream"],
         ["dessert": 1, "cake": 1, "cupcake": 0.9, "ice_cream": 1, "chocolate": 0.9, "cookie": 0.8, "donut": 0.8, "pastry": 0.8, "pie": 0.7, "birthday_cake": 0.7, "candy": 0.7]),
        (["dog", "dogs", "puppy", "puppies", "doggo", "pup"], ["dog": 1, "canine": 0.9, "retriever": 0.9, "husky": 0.9, "bulldog": 0.9, "terrier": 0.9]),
        (["cat", "cats", "kitten", "kitty", "kittens"], ["cat": 1, "adult_cat": 1, "kitten": 1, "feline": 0.9]),
        (["pet", "pets"], ["dog": 0.9, "cat": 0.9, "adult_cat": 0.9, "kitten": 0.9, "canine": 0.7, "feline": 0.7, "rabbit": 0.6, "hamster": 0.6, "goldfish": 0.5, "parrot": 0.5]),
        (["animal", "animals", "wildlife", "zoo"],
         ["animal": 1, "mammal": 0.8, "bird": 0.7, "dog": 0.7, "cat": 0.7, "horse": 0.7, "cow": 0.7, "elephant": 0.8, "lion": 0.8, "tiger": 0.8, "zoo": 0.8, "fish": 0.6, "reptile": 0.6]),
        (["bird", "birds"], ["bird": 1, "parrot": 0.9, "eagle": 0.9, "owl": 0.9, "peacock": 0.9, "pigeon": 0.9, "sparrow": 0.9, "swan": 0.9, "gull": 0.8]),
        (["people", "person", "friends", "friend", "group", "crowd", "family", "selfie", "portrait", "gathering", "together", "buddies"],
         ["people": 1, "crowd": 0.8, "adult": 0.7, "child": 0.5, "teen": 0.6, "celebration": 0.3]),
        (["party", "celebration", "celebrate", "festival", "carnival", "fun"],
         ["celebration": 1, "balloon": 0.7, "birthday_cake": 0.6, "nightclub": 0.6, "disco_ball": 0.7, "crowd": 0.5, "fireworks": 0.5, "carnival": 0.8, "gift": 0.4, "people": 0.3, "deejay": 0.6, "concert": 0.5]),
        (["baby", "babies", "kid", "kids", "child", "children", "toddler", "cute"],
         ["baby": 1, "child": 1, "toy": 0.5, "stroller": 0.4, "crib": 0.5, "pacifier": 0.6, "playground": 0.5, "kitten": 0.5]),
        (["wedding", "bride", "groom", "marriage"],
         ["wedding": 1, "bride": 1, "groom": 1, "wedding_dress": 0.9, "wedding_cake": 0.9, "bridesmaid": 0.8, "ceremony": 0.5, "bouquet": 0.4]),
        (["birthday", "bday"], ["birthday_cake": 1, "celebration": 0.7, "balloon": 0.6, "candle": 0.5, "cake": 0.5, "gift": 0.4]),
        (["car", "cars", "vehicle", "vehicles", "auto", "automobile", "drive", "driving"],
         ["car": 1, "automobile": 1, "sportscar": 0.9, "suv": 0.9, "jeep": 0.8, "police_car": 0.8, "formula_one_car": 0.8, "convertible": 0.8, "vehicle": 0.7, "limousine": 0.7, "van": 0.6, "road": 0.4, "dashboard": 0.5, "traffic_light": 0.3]),
        (["bike", "bikes", "bicycle", "cycling", "cycle", "motorcycle", "motorbike", "scooter"],
         ["bicycle": 1, "cycling": 1, "motorcycle": 1, "scooter": 0.8, "motocross": 0.7, "motorsport": 0.6]),
        (["travel", "trip", "vacation", "holiday", "tour", "tourist", "journey"],
         ["beach": 0.6, "island": 0.5, "luggage": 0.8, "suitcase": 0.7, "airport": 0.6, "airplane": 0.6, "monument": 0.5, "cityscape": 0.4, "mountain": 0.4, "tent": 0.4, "backpack": 0.5, "map": 0.4, "passport": 0.7]),
        (["plane", "airplane", "flight", "flying", "aircraft", "airport", "aeroplane"],
         ["airplane": 1, "aircraft": 1, "airport": 0.9, "helicopter": 0.7, "hangar": 0.5, "airshow": 0.7]),
        (["train", "trains", "railway", "railroad", "metro", "station"], ["train_real": 1, "train": 1, "railroad": 0.9, "train_station": 0.9, "track_rail": 0.8, "monorail": 0.8, "tramway": 0.7]),
        (["boat", "boats", "ship", "sailing", "yacht", "ferry", "cruise"],
         ["boat": 1, "sailboat": 0.9, "yacht": 0.9, "watercraft": 0.9, "cruise_ship": 0.9, "speedboat": 0.9, "canoe": 0.8, "kayak": 0.8, "rowboat": 0.8, "harbour": 0.6]),
        (["bus", "buses", "truck", "lorry", "tractor"], ["bus": 1, "truck": 1, "semi_truck": 0.9, "van": 0.6, "tractor": 0.9]),
        (["city", "urban", "town", "downtown", "skyline"], ["cityscape": 1, "street": 0.8, "building": 0.8, "skyscraper": 0.9, "road": 0.5, "storefront": 0.5, "apartment": 0.5]),
        (["street", "road", "roads", "highway", "traffic"], ["street": 1, "road": 1, "road_other": 0.9, "crosswalk": 0.7, "traffic_light": 0.7, "sidewalk": 0.7, "street_sign": 0.7, "car": 0.3]),
        (["building", "buildings", "architecture", "house", "home", "apartment"],
         ["building": 1, "house_single": 0.9, "domicile": 0.9, "apartment": 0.9, "skyscraper": 0.8, "structure": 0.7, "tower": 0.6]),
        (["room", "indoor", "indoors", "inside", "interior", "bedroom", "kitchen", "bathroom"],
         ["interior_room": 1, "living_room": 0.9, "bedroom": 0.9, "kitchen_room": 0.9, "bathroom_room": 0.9, "dining_room": 0.8, "furniture": 0.7, "sofa": 0.6, "bed": 0.6, "table": 0.5, "chair": 0.5]),
        (["monument", "temple", "church", "castle", "statue", "historic", "heritage", "ruins", "landmark"],
         ["monument": 1, "statue": 0.8, "ruins": 0.8, "castle": 0.9, "belltower": 0.8, "tower": 0.7, "dome": 0.7, "arch": 0.6, "pyramid": 0.8, "megalith": 0.7, "obelisk": 0.7, "museum": 0.6]),
        (["screenshot", "screenshots", "screen", "screencap"], ["screenshot": 1]),
        (["document", "documents", "paper", "text", "notes", "note", "receipt", "bill", "form", "handwriting"],
         ["document": 1, "printed_page": 0.9, "handwriting": 0.9, "receipt": 0.9, "book": 0.4, "newspaper": 0.5, "sticky_note": 0.6, "diagram": 0.4]),
        (["book", "books", "reading", "study", "studying", "library", "class", "classroom", "school", "university", "college", "lecture"],
         ["book": 1, "library": 0.9, "classroom": 0.9, "bookshelf": 0.8, "chalkboard": 0.8, "whiteboard": 0.8, "document": 0.4, "printed_page": 0.5, "laptop": 0.3, "graduation": 0.8, "desk": 0.4]),
        (["laptop", "computer", "work", "office", "coding", "desk", "pc", "monitor"],
         ["laptop": 1, "computer": 1, "computer_monitor": 0.9, "computer_keyboard": 0.8, "computer_tower": 0.8, "desk": 0.8, "office_supplies": 0.5, "cubicle": 0.6, "monitor_lizard": 0]),
        (["phone", "mobile", "smartphone"], ["phone": 1, "consumer_electronics": 0.4]),
        (["music", "concert", "guitar", "piano", "band", "singing", "dj"],
         ["music": 1, "concert": 1, "guitar": 0.9, "piano": 0.9, "drum": 0.8, "microphone": 0.7, "performance": 0.7, "speakers_music": 0.7, "musical_instrument": 0.8, "singer": 0.8, "deejay": 0.7, "orchestra": 0.8]),
        (["sport", "sports", "football", "soccer", "cricket", "gym", "workout", "exercise", "match", "game"],
         ["sport": 1, "soccer": 0.9, "football": 0.9, "stadium": 0.8, "athletics": 0.8, "workout": 0.8, "health_club": 0.7, "gymnastics": 0.7, "ballgames": 0.8, "cricket_sport": 1, "basketball": 0.9, "tennis": 0.9, "volleyball": 0.9, "scoreboard": 0.6, "dumbbell": 0.7, "treadmill": 0.7]),
        (["swim", "swimming", "pool", "diving"], ["pool": 1, "swimming": 1, "swimsuit": 0.8, "diving": 0.8, "jacuzzi": 0.6, "waterpolo": 0.7]),
        (["art", "painting", "drawing", "sketch", "graffiti", "illustration"], ["art": 1, "painting": 1, "illustrations": 0.9, "graffiti": 0.9, "easel": 0.8, "paintbrush": 0.8, "diagram": 0.3]),
        (["fire", "bonfire", "campfire", "camp", "camping", "tent"], ["fire": 1, "flame": 0.9, "embers": 0.7, "camping": 1, "tent": 0.9, "fireplace": 0.6, "firecracker": 0.4]),
        (["fireworks", "firework"], ["fireworks": 1, "pyrotechnics": 0.9, "sparkler": 0.7, "firecracker": 0.8]),
        (["christmas", "xmas", "newyear"], ["christmas_tree": 1, "christmas_decoration": 1, "santa_claus": 0.9, "gift": 0.6, "wreath": 0.8, "holly": 0.7, "snowman": 0.6]),
        (["shopping", "shop", "store", "market", "mall"], ["storefront": 0.9, "interior_shop": 1, "shopping_cart": 0.9, "purse": 0.5, "bag": 0.5, "clothing": 0.5]),
        (["clothes", "clothing", "fashion", "outfit", "dress", "shoes"], ["clothing": 1, "footwear": 0.9, "shoes": 0.9, "jeans": 0.8, "jacket": 0.8, "gown": 0.7, "suit": 0.7, "hat": 0.7, "sneaker": 0.8]),
        (["toy", "toys", "game", "games", "playing"], ["toy": 1, "stuffed_animals": 0.8, "blocks": 0.7, "doll": 0.8, "puzzles": 0.7, "board_game": 0.8, "videogame": 0.8, "playground": 0.6]),
        (["horse", "horses", "riding"], ["horse": 1, "equestrian": 0.9, "saddle": 0.7, "jockey_horse": 0.8, "dressage": 0.7]),
        (["farm", "village", "countryside", "field", "paddy", "agriculture"], ["farm": 1, "agriculture": 0.9, "rice_field": 0.9, "barn": 0.8, "tractor": 0.7, "grass": 0.5, "cow": 0.5, "orchard": 0.7, "vineyard": 0.7])
    ]

    /// Strong, specific interpretations of a query word, or nil when the word isn't a known concept.
    static func labels(for token: String) -> [String: Float]? {
        var merged: [String: Float] = [:]
        for group in groups where group.aliases.contains(token) || group.aliases.contains(singular(token)) {
            for (label, weight) in group.labels { merged[label] = max(merged[label] ?? 0, weight) }
        }
        return merged.isEmpty ? nil : merged
    }

    /// Plural / inflection-tolerant exact label-word match ("cars" → `car`, but never `carrot`).
    static func directMatch(token: String, label: String) -> Bool {
        for word in label.split(separator: "_").map(String.init) {
            if word == token { return true }
            if word.count >= 3, token.hasPrefix(word), token.count - word.count <= 2 { return true }
        }
        return false
    }

    private static func singular(_ word: String) -> String {
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("s"), word.count > 3 { return String(word.dropLast()) }
        return word
    }
}
