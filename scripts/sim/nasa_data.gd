extends RefCounted
## Curated, embedded NASA open-data facts used by the simulation.
##
## Space-weather events are ARCHIVED records of real solar events catalogued in
## NASA's Space Weather Database Of Notifications, Knowledge, Information (DONKI).
## They are never presented as live. A separate optional live request
## (see scripts/net/live_donki.gd) may add current flares and is labeled LIVE only
## after it succeeds.

const DONKI_URL := "https://kauai.ccmc.gsfc.nasa.gov/DONKI/"
const DONKI_API := "https://api.nasa.gov/DONKI/"

## type: FLR = solar flare, SEP = solar energetic particle (radiation) event,
## CME = coronal mass ejection. "power" scales the in-game radiation dose (0-40).
const SPACE_WEATHER_ARCHIVE: Array[Dictionary] = [
	{
		"id": "2017-09-06-X9.3", "type": "FLR", "date": "6 Sep 2017", "class": "X9.3",
		"headline": "X9.3 solar flare",
		"detail": "Peaked at 12:02 UTC from sunspot region 2673. It was the strongest flare of Solar Cycle 24.",
		"power": 28,
	},
	{
		"id": "2017-09-10-X8.2", "type": "SEP", "date": "10 Sep 2017", "class": "X8.2",
		"headline": "X8.2 flare + radiation storm",
		"detail": "A fast CME and flood of solar protons followed. Particles even reached the ground on Earth and lit up Mars' sky.",
		"power": 36,
	},
	{
		"id": "2021-10-28-X1.0", "type": "SEP", "date": "28 Oct 2021", "class": "X1.0",
		"headline": "X1.0 flare + radiation storm",
		"detail": "Solar protons were so energetic that detectors on the ground measured them (a 'Ground Level Enhancement').",
		"power": 22,
	},
	{
		"id": "2024-05-10-CME", "type": "CME", "date": "10 May 2024", "class": "Series of CMEs",
		"headline": "Giant May 2024 solar storm",
		"detail": "Several CMEs from sunspot region 3664 hit Earth, causing the strongest geomagnetic storm in over 20 years and auroras seen far from the poles.",
		"power": 30,
	},
	{
		"id": "2024-05-14-X8.7", "type": "FLR", "date": "14 May 2024", "class": "X8.7",
		"headline": "X8.7 solar flare",
		"detail": "From the same sunspot region 3664. It was the largest flare of Solar Cycle 25 at that time.",
		"power": 26,
	},
	{
		"id": "2024-06-08-SEP", "type": "SEP", "date": "8 Jun 2024", "class": "M9 flare",
		"headline": "Strong proton storm",
		"detail": "Linked to an M-class flare as region 3664 came back around. It was one of the strongest proton events of Solar Cycle 25.",
		"power": 30,
	},
	{
		"id": "2024-10-03-X9.0", "type": "FLR", "date": "3 Oct 2024", "class": "X9.0",
		"headline": "X9.0 solar flare",
		"detail": "Peaked at 12:18 UTC from sunspot region 3842, the strongest flare of Solar Cycle 25 so far.",
		"power": 30,
	},
	{
		"id": "2024-10-09-CME", "type": "CME", "date": "9 Oct 2024", "class": "X1.8 + halo CME",
		"headline": "Fast CME from an X1.8 flare",
		"detail": "A full-halo CME left the Sun early on 9 Oct and hit Earth the next day, causing a severe storm.",
		"power": 24,
	},
	{
		"id": "2025-11-11-X5.1", "type": "SEP", "date": "11 Nov 2025", "class": "X5.1",
		"headline": "X5.1 flare + radiation storm",
		"detail": "Peaked around 10:04 UTC. Energetic protons caused a rare Ground Level Enhancement (GLE 77).",
		"power": 34,
	},
]

## Short, plain-language explanations shown in context.
const TERMS := {
	"day": "Mission day: one Earth day of work at the base. A full Moon day-and-night lasts about 29.5 Earth days!",
	"sol": "Sol: a day on Mars (24 h 39 min). On the Moon we count Earth days.",
	"dose": "Radiation dose: how much invisible space energy the crew's bodies have soaked up. Too much over time is unsafe.",
	"flare": "Solar flare: a giant flash of light and energy on the Sun.",
	"sep": "Radiation storm: super-fast particles (protons) from the Sun. They can reach the Moon in under an hour.",
	"cme": "CME: a huge cloud of hot gas thrown off the Sun. It takes 1 to 3 days to travel to us.",
	"shield": "Shielding: thick walls of moon dirt or water that block radiation, like a lead apron at the dentist.",
	"gcr": "Cosmic rays: particles from far-away exploding stars. They are so strong that walls only stop some of them.",
	"microgravity": "Low gravity: on the Moon you weigh 1/6 of your Earth weight, so muscles and bones work less.",
	"electrolysis": "Splitting water: electricity can break water (H2O) into hydrogen and the oxygen we breathe.",
	"delay": "Signal delay: radio travels at light speed, but the Moon is 384,400 km away, so every message takes about 1.3 seconds.",
	"regolith": "Regolith: the Moon's dusty, sharp soil. It sticks to everything!",
}

## Real findings used for "Space facts", consequences and the results screen.
const FACTS := {
	"apollo_dust": "Apollo 12 astronauts found that their lander's rocket blast had sandblasted the nearby Surveyor 3 probe with moon dust.",
	"no_wind": "The Moon has no air and no wind. Dust only flies when rockets, rovers or boots kick it up.",
	"lcross": "In 2009 NASA's LCROSS mission crashed into a dark crater near the Moon's South Pole and found water ice.",
	"veggie": "NASA's Veggie garden on the Space Station grew red romaine lettuce that astronauts ate in 2015.",
	"zinnia": "In 2016 astronaut Scott Kelly rescued moldy, wilting zinnia flowers in space by changing their water and air flow.",
	"osdr_muscle": "NASA's Open Science Data Repository (OSDR) holds studies showing that mice and astronauts lose muscle and bone in low gravity.",
	"exercise": "Astronauts on the Space Station exercise about 2 hours every day to keep muscles and bones strong.",
	"twins": "NASA's Twins Study (data in OSDR) compared astronaut Scott Kelly after a year in space with his twin Mark on Earth.",
	"artemis_shelter": "On Artemis missions, the Orion crew can build a storm shelter by packing supplies around themselves during a solar radiation storm.",
	"artemis_mare": "Artemis I flew two test 'phantom' torsos (Helga and Zohar) to measure radiation around the Moon. Zohar wore a radiation vest.",
	"water_shield": "Water is great shielding. Mission planners like water walls because the same water can be drunk or split into oxygen.",
	"gcr_hard": "Cosmic rays are much harder to block than solar storms, so every day in space adds a little radiation dose.",
	"oxygen_iss": "On the Space Station, machines make oxygen by splitting water with electricity.",
	"south_pole": "At the Moon's South Pole the Sun stays low on the horizon, so mountain and crater shadows sweep across the ground.",
	"micrometeoroid": "Tiny space rocks hit the Moon all the time. With no air to burn them up, even grain-sized ones can dent metal.",
	"light_delay": "A radio message takes about 1.3 seconds to reach the Moon, but 3 to 22 minutes to reach Mars!",
	"flare_speed": "Light from a solar flare reaches us in about 8 minutes. The fastest solar protons can arrive minutes after that.",
}

## Dataset attribution shown in the NASA Data screen.
const SOURCES: Array[Dictionary] = [
	{
		"name": "NASA DONKI - Space Weather Database",
		"url": "kauai.ccmc.gsfc.nasa.gov/DONKI  |  api.nasa.gov (DONKI API)",
		"use": "Real solar flares (FLR), radiation storms (SEP) and CMEs become the space-weather events in your mission. Each event card shows the real date and class. These records are ARCHIVED inside the game. When the game can reach NASA's live DONKI API, it also shows how active the real Sun was in the last 30 days and adds a 'Today's Sun' event; that event is labeled LIVE.",
	},
	{
		"name": "NASA Open Science Data Repository (OSDR / GeneLab)",
		"url": "osdr.nasa.gov",
		"use": "Findings about how low gravity and radiation affect muscles, bones and bodies (rodent research, the NASA Twins Study) shape the crew health events and the radiation dose limit idea.",
	},
	{
		"name": "Artemis I & Orion radiation experiments",
		"url": "nasa.gov/artemis",
		"use": "The storm-shelter choice copies how the Orion crew can shelter during a radiation storm. The MARE 'phantom' torsos measured radiation around the Moon.",
	},
	{
		"name": "LCROSS & Lunar Reconnaissance Orbiter",
		"url": "nasa.gov/lcross  |  lunar.gsfc.nasa.gov",
		"use": "Water ice in dark South Pole craters, low sun angles and long shadows set the scene for your outpost and the ice-discovery event.",
	},
	{
		"name": "Apollo 12 / Surveyor 3, ISS Veggie & ISS life support",
		"url": "nasa.gov",
		"use": "Lander dust blasts, growing lettuce in space and making oxygen from water with electricity are all based on real NASA missions.",
	},
]


static func pick_archive_events(rng: RandomNumberGenerator, count: int) -> Array[Dictionary]:
	var pool: Array[Dictionary] = SPACE_WEATHER_ARCHIVE.duplicate(true)
	var chosen: Array[Dictionary] = []
	while chosen.size() < count and not pool.is_empty():
		var index := rng.randi_range(0, pool.size() - 1)
		chosen.append(pool[index])
		pool.remove_at(index)
	return chosen


## Convert a GOES flare class such as "X1.2" or "M5.4" into an in-game power.
static func power_from_class(class_type: String) -> int:
	var letter := class_type.substr(0, 1).to_upper()
	var magnitude := class_type.substr(1).to_float()
	match letter:
		"X":
			return clampi(20 + roundi(magnitude * 1.6), 20, 38)
		"M":
			return clampi(10 + roundi(magnitude), 10, 20)
		_:
			return 8
