import Foundation

/// Maps Vision `ClassifyImageRequest` identifiers to insurable household items.
///
/// Vision's classifier knows ~1,300 labels, most of which are scenes, food, animals, or
/// activities. Only labels listed here become inventory candidates. Every key below is a
/// real identifier from `ClassifyImageRequest` (revision 2) — keep it that way.
nonisolated struct CatalogEntry: Equatable, Hashable, Sendable {
    let name: String
    let category: ItemCategory
}

nonisolated enum LabelCatalog {
    static func entry(for identifier: String) -> CatalogEntry? {
        entries[identifier]
    }

    static var identifiers: Set<String> { Set(entries.keys) }

    private static let entries: [String: CatalogEntry] = {
        var map: [String: CatalogEntry] = [:]
        func add(_ category: ItemCategory, _ pairs: [(String, String)]) {
            for (id, name) in pairs { map[id] = CatalogEntry(name: name, category: category) }
        }

        add(.electronics, [
            ("television", "Television"),
            ("computer", "Computer"),
            ("laptop", "Laptop"),
            ("computer_monitor", "Computer monitor"),
            ("computer_tower", "Desktop computer"),
            ("computer_keyboard", "Keyboard"),
            ("computer_mouse", "Computer mouse"),
            ("printer", "Printer"),
            ("phone", "Phone"),
            ("camera", "Camera"),
            ("headphones", "Headphones"),
            ("speakers_music", "Speakers"),
            ("stereo", "Stereo system"),
            ("turntable", "Turntable"),
            ("gamepad", "Game controller"),
            ("videogame", "Video game console"),
            ("joystick", "Joystick"),
            ("drone_machine", "Drone"),
            ("microphone", "Microphone"),
            ("consumer_electronics", "Electronic device"),
            ("calculator", "Calculator"),
            ("typewriter", "Typewriter"),
            ("binoculars", "Binoculars"),
            ("telescope", "Telescope"),
            ("microscope", "Microscope"),
            ("tripod", "Tripod"),
        ])
        add(.appliances, [
            ("refrigerator", "Refrigerator"),
            ("dishwasher", "Dishwasher"),
            ("laundry_machine", "Washer / dryer"),
            ("microwave", "Microwave"),
            ("kitchen_oven", "Oven"),
            ("oven", "Oven"),
            ("stove", "Stove"),
            ("toaster", "Toaster"),
            ("toaster_oven", "Toaster oven"),
            ("blender", "Blender"),
            ("juicer", "Juicer"),
            ("kettle", "Kettle"),
            ("vacuum", "Vacuum cleaner"),
            ("electric_fan", "Electric fan"),
            ("iron_clothing", "Clothes iron"),
            ("thermostat", "Thermostat"),
            ("grill", "Grill"),
            ("treadmill", "Treadmill"),
            ("mower", "Lawn mower"),
            ("sewing", "Sewing machine"),
            ("appliance", "Appliance"),
        ])
        add(.furniture, [
            ("sofa", "Sofa"),
            ("armchair", "Armchair"),
            ("chair", "Chair"),
            ("chair_other", "Chair"),
            ("swivel_chair", "Office chair"),
            ("folding_chair", "Folding chair"),
            ("chaise", "Chaise lounge"),
            ("stool", "Stool"),
            ("bench", "Bench"),
            ("table", "Table"),
            ("desk", "Desk"),
            ("bed", "Bed"),
            ("crib", "Crib"),
            ("high_chair", "High chair"),
            ("bookshelf", "Bookshelf"),
            ("cabinet", "Cabinet"),
            ("hammock", "Hammock"),
            ("furniture", "Furniture"),
        ])
        add(.kitchen, [
            ("cookware", "Cookware"),
            ("pan", "Pan"),
            ("pot_cooking", "Cooking pot"),
            ("steamer_cookware", "Steamer"),
            ("tableware", "Tableware"),
            ("plate", "Plates"),
            ("bowl", "Bowls"),
            ("cup", "Cups"),
            ("mug", "Mugs"),
            ("drinking_glass", "Drinking glasses"),
            ("teapot", "Teapot"),
            ("decanter", "Decanter"),
            ("knife", "Knives"),
            ("cutting_board", "Cutting board"),
            ("utensil", "Utensils"),
            ("wine_bottle", "Wine collection"),
            ("thermos", "Thermos"),
            ("cakestand", "Cake stand"),
        ])
        add(.decor, [
            ("lamp", "Lamp"),
            ("chandelier", "Chandelier"),
            ("lantern", "Lantern"),
            ("candlestick", "Candlestick"),
            ("clock", "Clock"),
            ("vase", "Vase"),
            ("curtain", "Curtains"),
            ("pillow", "Pillows"),
            ("bedding", "Bedding"),
            ("textile", "Rug / textile"),
            ("frame", "Picture frame"),
            ("decorative_plant", "Decorative plant"),
            ("bonsai", "Bonsai"),
            ("terrarium", "Terrarium"),
            ("fishtank", "Aquarium"),
            ("aquarium", "Aquarium"),
            ("christmas_decoration", "Holiday decorations"),
        ])
        add(.art, [
            ("painting", "Painting"),
            ("art", "Artwork"),
            ("statue", "Sculpture"),
            ("figurine", "Figurine"),
            ("stained_glass", "Stained glass"),
            ("illustrations", "Framed print"),
            ("trophy", "Trophy"),
            ("medal", "Medal"),
            ("coin", "Coin collection"),
            ("record", "Record collection"),
        ])
        add(.jewelry, [
            ("jewelry", "Jewelry"),
            ("watch", "Watch"),
            ("timepiece", "Watch"),
            ("tiara", "Tiara"),
            ("eyeglasses", "Eyeglasses"),
            ("sunglasses", "Sunglasses"),
        ])
        add(.clothing, [
            ("clothing", "Clothing"),
            ("jacket", "Jacket"),
            ("suit", "Suit"),
            ("gown", "Gown"),
            ("wedding_dress", "Wedding dress"),
            ("footwear", "Shoes"),
            ("shoes", "Shoes"),
            ("sneaker", "Sneakers"),
            ("boot", "Boots"),
            ("high_heel", "Heels"),
            ("purse", "Handbag"),
            ("bag", "Bag"),
            ("backpack", "Backpack"),
            ("briefcase", "Briefcase"),
            ("luggage", "Luggage"),
            ("suitcase", "Suitcase"),
            ("hat", "Hat"),
            ("scarf", "Scarf"),
            ("wallet", "Wallet"),
        ])
        add(.musical, [
            ("piano", "Piano"),
            ("guitar", "Guitar"),
            ("violin", "Violin"),
            ("cello", "Cello"),
            ("harp", "Harp"),
            ("ukulele", "Ukulele"),
            ("drum", "Drum kit"),
            ("bongo_drum", "Bongo drums"),
            ("saxophone", "Saxophone"),
            ("trumpet", "Trumpet"),
            ("trombone", "Trombone"),
            ("tuba", "Tuba"),
            ("flute", "Flute"),
            ("clarinet", "Clarinet"),
            ("accordion", "Accordion"),
            ("xylophone", "Xylophone"),
            ("organ_instrument", "Organ"),
            ("tambourine", "Tambourine"),
            ("musical_instrument", "Musical instrument"),
            ("string_instrument", "String instrument"),
            ("brass_music", "Brass instrument"),
            ("woodwind", "Woodwind instrument"),
        ])
        add(.sports, [
            ("bicycle", "Bicycle"),
            ("dumbbell", "Dumbbells"),
            ("barbell", "Barbell"),
            ("weight_scale", "Scale"),
            ("golf_club", "Golf clubs"),
            ("racquet", "Racquet"),
            ("surfboard", "Surfboard"),
            ("skateboard", "Skateboard"),
            ("snowboard", "Snowboard"),
            ("ski_equipment", "Skis"),
            ("kayak", "Kayak"),
            ("canoe", "Canoe"),
            ("tent", "Tent"),
            ("helmet", "Helmet"),
            ("sports_equipment", "Sports equipment"),
            ("rollerskates", "Roller skates"),
            ("ice_skates", "Ice skates"),
            ("scooter", "Scooter"),
            ("stroller", "Stroller"),
            ("car_seat", "Car seat"),
        ])
        add(.tools, [
            ("toolbox", "Toolbox"),
            ("tool", "Tools"),
            ("power_saw", "Power saw"),
            ("chainsaw", "Chainsaw"),
            ("hammer", "Hammer"),
            ("wrench", "Wrench"),
            ("screwdriver", "Screwdrivers"),
            ("pliers", "Pliers"),
            ("ratchet", "Ratchet set"),
            ("caliper", "Caliper"),
            ("measuring_tape", "Measuring tape"),
            ("flashlight", "Flashlight"),
            ("wheelbarrow", "Wheelbarrow"),
            ("rake", "Rake"),
            ("watering_can", "Watering can"),
            ("sprinkler", "Sprinkler"),
            ("extinguisher", "Fire extinguisher"),
            ("solar_panel", "Solar panel"),
        ])
        add(.books, [
            ("book", "Books"),
            ("magazine", "Magazines"),
            ("cd", "CDs"),
            ("cassette", "Cassettes"),
            ("board_game", "Board games"),
        ])
        add(.toys, [
            ("toy", "Toys"),
            ("doll", "Doll"),
            ("stuffed_animals", "Stuffed animals"),
            ("train_toy", "Toy train"),
            ("vehicle_toy", "Toy vehicle"),
            ("blocks", "Building blocks"),
            ("puzzles", "Puzzles"),
            ("chess", "Chess set"),
            ("tricycle", "Tricycle"),
        ])
        return map
    }()
}
