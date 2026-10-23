import 'species.dart';

/// Symptom-led reference for South African cattle, goat, sheep and horse
/// conditions.
///
/// This is deliberately not a diagnosis. Several of these are controlled
/// diseases under the Animal Diseases Act 35 of 1984, where the legally correct
/// action is to call the state veterinarian rather than treat on farm, so the
/// matcher is tuned to surface those first even on a weak symptom match.
/// It gives no drug doses: treatment belongs to a vet.
class Symptom {
  final String id;
  final String label;
  final String group;

  /// Which species can show this sign. Null means all of them.
  final Set<Species>? only;

  const Symptom(this.id, this.label, this.group, [this.only]);

  bool appliesTo(Species s) => only == null || only!.contains(s);
}

const _ruminants = {Species.cattle, Species.goat, Species.sheep};
const _smallStock = {Species.goat, Species.sheep};
const _horse = {Species.horse};
const _all = {Species.cattle, Species.goat, Species.sheep, Species.horse};

enum Urgency {
  notifiable('Call the state vet now', 'This is a controlled disease. By law you must report it.'),
  emergency('Urgent, same day', 'Get a vet out today. Animals can die quickly.'),
  soon('See a vet this week', 'Treatable, but do not leave it.'),
  monitor('Monitor and manage', 'Handle on farm, watch for change.');

  final String label;
  final String guidance;
  const Urgency(this.label, this.guidance);
}

class LivestockCondition {
  final String name;
  final String plainName;
  final List<String> symptomIds;
  final Urgency urgency;
  final String whatItIs;
  final List<String> actions;

  /// The species this can affect.
  final Set<Species> species;

  const LivestockCondition({
    required this.species,
    required this.name,
    required this.plainName,
    required this.symptomIds,
    required this.urgency,
    required this.whatItIs,
    required this.actions,
  });
}

class ConditionMatch {
  final LivestockCondition condition;
  final double score;
  const ConditionMatch(this.condition, this.score);
}

class LivestockDatabase {
  static const symptoms = <Symptom>[
    // Mouth and feet
    Symptom('blisters_mouth', 'Blisters or sores in the mouth', 'Mouth & feet', {Species.cattle, Species.goat, Species.sheep}),
    Symptom('drooling', 'Drooling / stringy saliva', 'Mouth & feet'),
    Symptom('blisters_feet', 'Blisters between the hooves', 'Mouth & feet', {Species.cattle, Species.goat, Species.sheep}),
    Symptom('lameness', 'Limping or unwilling to walk', 'Mouth & feet'),
    Symptom('foul_hoof', 'Foul smell or rot between the toes', 'Mouth & feet', _smallStock),
    Symptom('hoof_heat', 'Heat in one hoof, strong pulse at the foot', 'Mouth & feet', _horse),
    Symptom('laminitis', 'Reluctant to walk, rocking back onto the heels', 'Mouth & feet', _horse),
    Symptom('scabby_lips', 'Scabs on the lips, nose or gums', 'Mouth & feet', _smallStock),
    Symptom('swollen_tongue', 'Swollen, bluish tongue', 'Mouth & feet', _ruminants),
    // General
    Symptom('not_eating', 'Off feed / not grazing', 'General'),
    Symptom('depressed', 'Dull, standing apart from the others', 'General'),
    Symptom('fever', 'Fever, hot ears and nose', 'General'),
    Symptom('sudden_death', 'Sudden death with no warning', 'General'),
    Symptom('weight_loss', 'Losing condition over weeks', 'General'),
    Symptom('stiffness', 'Stiff, moving with difficulty', 'General'),
    Symptom('aggression', 'Strange aggression, bellowing or fearless behaviour', 'General'),
    Symptom('paralysis', 'Back legs weak or paralysed', 'General'),
    // Skin and wool
    Symptom('skin_nodules', 'Hard lumps or nodules on the skin', 'Skin', {Species.cattle}),
    Symptom('swelling', 'Swelling under the skin', 'Skin'),
    Symptom('wool_loss', 'Wool coming off, rubbing and itching', 'Skin', {Species.sheep}),
    Symptom('maggots', 'Maggots, or a foul smell from wool or a wound', 'Skin', _smallStock),
    Symptom('lymph_lumps', 'Firm lump near a lymph gland (jaw, shoulder, flank)', 'Skin', _smallStock),
    Symptom('itchy_mane', 'Rubbing mane and tail raw, hair loss', 'Skin', _horse),
    // Head
    Symptom('eye_discharge', 'Weeping or cloudy eye', 'Head'),
    Symptom('nasal_discharge', 'Runny nose', 'Head'),
    Symptom('swollen_head', 'Swollen eyelids, lips or the hollows above the eyes', 'Head', _horse),
    Symptom('lump_throat', 'Hot swelling under the jaw or throat, thick yellow nasal discharge', 'Head', _horse),
    Symptom('bottle_jaw', 'Soft swelling under the jaw (bottle jaw)', 'Head', _smallStock),
    Symptom('muscle_spasm', 'Stiff jaw, third eyelid showing, muscle spasms', 'Nerves', _horse),
    // Chest
    Symptom('coughing', 'Coughing', 'Chest'),
    Symptom('breathing', 'Laboured breathing', 'Chest'),
    Symptom('frothy_nose', 'Froth from the nose', 'Chest', _horse),
    // Gut
    Symptom('diarrhoea', 'Scouring / diarrhoea', 'Gut'),
    Symptom('bloat', 'Swollen left flank (bloat)', 'Gut', _ruminants),
    Symptom('colic_pain', 'Pawing, rolling, kicking or looking at the belly', 'Gut', _horse),
    // Blood
    Symptom('dark_urine', 'Red or dark urine', 'Blood'),
    Symptom('pale_gums', 'Pale gums and eyelids', 'Blood'),
    Symptom('jaundice', 'Yellow gums or eyes', 'Blood'),
    // Breeding
    Symptom('abortion', 'Aborted or lost the young', 'Breeding'),
    Symptom('late_pregnancy', 'Heavily pregnant and unwell', 'Breeding', _smallStock),
    Symptom('udder', 'Hot, hard or swollen udder', 'Breeding', _ruminants),
    Symptom('milk_drop', 'Sudden drop in milk', 'Breeding', _ruminants),
    Symptom('weak_young', 'Lamb, kid or calf weak, will not suckle', 'Breeding', _ruminants),
    // Nerves
    Symptom('circling', 'Circling, pressing head, odd behaviour', 'Nerves'),
  ];

  static const conditions = <LivestockCondition>[
    // ------------------------------------------------ controlled diseases
    LivestockCondition(
      species: {Species.cattle, Species.goat, Species.sheep},
      name: 'Foot-and-Mouth Disease',
      plainName: 'Foot-and-Mouth: Report Immediately',
      symptomIds: ['blisters_mouth', 'drooling', 'blisters_feet', 'lameness', 'fever', 'not_eating', 'milk_drop'],
      urgency: Urgency.notifiable,
      whatItIs:
          'A highly contagious virus that spreads through a herd and to neighbouring farms very fast. '
          'It is a controlled disease in South Africa and outbreaks trigger movement bans. '
          'Goats and sheep often show only mild signs but still spread it.',
      actions: [
        'Stop all animal movement on and off the farm immediately',
        'Phone your state veterinarian today. This is a legal duty',
        'Keep sick animals away from the rest of the herd',
        'Do not visit other farms, and disinfect boots and vehicle tyres',
      ],
    ),
    LivestockCondition(
      species: _all,
      name: 'Anthrax',
      plainName: 'Possible Anthrax: Do Not Open the Carcass',
      symptomIds: ['sudden_death', 'fever', 'swelling', 'not_eating'],
      urgency: Urgency.notifiable,
      whatItIs:
          'A bacterial disease that usually shows as sudden death, often with dark blood from the nose or anus. '
          'It is dangerous to people and is a controlled disease. Horses can catch it too.',
      actions: [
        'Do NOT cut open or skin the carcass. This spreads spores that last decades',
        'Phone your state veterinarian immediately',
        'Keep people and other animals away from the carcass',
        'Wash thoroughly if you touched the animal',
      ],
    ),
    LivestockCondition(
      species: _all,
      name: 'Rabies',
      plainName: 'Possible Rabies: Keep Away and Call the Vet',
      symptomIds: ['aggression', 'paralysis', 'drooling', 'circling', 'sudden_death', 'not_eating'],
      urgency: Urgency.notifiable,
      whatItIs:
          'A fatal virus carried by dogs, jackals and mongooses and passed on by a bite. Livestock may turn '
          'aggressive or bellow strangely, drool, or lose the use of their back legs. It kills people too.',
      actions: [
        'Do not touch the saliva or put your hand in the animal\'s mouth',
        'Keep people, children and dogs away and call your state vet at once',
        'If anyone was bitten or licked on a cut, go to a clinic straight away',
        'Keep your dogs and horses vaccinated every year',
      ],
    ),
    LivestockCondition(
      species: {Species.cattle, Species.goat, Species.sheep},
      name: 'Brucellosis',
      plainName: 'Possible Contagious Abortion',
      symptomIds: ['abortion', 'swelling', 'weight_loss'],
      urgency: Urgency.notifiable,
      whatItIs:
          'A bacterial disease causing abortion in the last third of pregnancy. '
          'It infects people too, and is a controlled disease requiring testing.',
      actions: [
        'Do not handle the aborted young or afterbirth with bare hands',
        'Phone your state vet to arrange blood testing of the herd or flock',
        'Isolate the female that aborted',
        'Do not drink unpasteurised milk',
      ],
    ),
    LivestockCondition(
      species: {Species.cattle, Species.goat, Species.sheep},
      name: 'Rift Valley Fever',
      plainName: 'Possible Rift Valley Fever: Report It',
      symptomIds: ['abortion', 'sudden_death', 'fever', 'jaundice', 'diarrhoea', 'weak_young', 'not_eating'],
      urgency: Urgency.notifiable,
      whatItIs:
          'A mosquito-borne virus that follows heavy rain. It causes abortion storms and the death of newborn '
          'lambs and kids. People catch it from blood and aborted material, so it is a risk to you too.',
      actions: [
        'Phone your state vet. It is a reportable disease',
        'Wear gloves and a mask when handling dead or aborted animals, and bury them deep',
        'Do not drink raw milk',
        'Ask your vet about vaccinating before the next rainy season',
      ],
    ),
    LivestockCondition(
      species: {Species.cattle, Species.goat},
      name: 'Bovine Tuberculosis',
      plainName: 'Possible TB',
      symptomIds: ['coughing', 'weight_loss', 'breathing', 'swelling'],
      urgency: Urgency.notifiable,
      whatItIs:
          'A slow bacterial disease causing a chronic cough and steady wasting. '
          'It infects people through raw milk and is a controlled disease.',
      actions: [
        'Phone your state vet to arrange tuberculin testing',
        'Isolate the coughing animal',
        'Do not sell or move the animal until it has been tested',
        'Do not drink unpasteurised milk',
      ],
    ),
    LivestockCondition(
      species: {Species.sheep},
      name: 'Sheep Scab',
      plainName: 'Possible Sheep Scab: Report It',
      symptomIds: ['wool_loss', 'weight_loss', 'not_eating'],
      urgency: Urgency.notifiable,
      whatItIs:
          'A mite that makes sheep itch, rub and lose wool in patches. It is a controlled disease and an '
          'infected flock can be put under movement restrictions until it is dipped.',
      actions: [
        'Phone your state vet. Do not move the flock',
        'Keep sheep away from neighbours\' fences',
        'The vet will tell you which dip or treatment to use and how often',
      ],
    ),
    LivestockCondition(
      species: _horse,
      name: 'African Horse Sickness',
      plainName: 'Possible African Horse Sickness: Report It',
      symptomIds: ['frothy_nose', 'swollen_head', 'fever', 'breathing', 'coughing', 'sudden_death', 'not_eating'],
      urgency: Urgency.notifiable,
      whatItIs:
          'A midge-borne virus that is common in warm, wet months. It can cause fever, froth from the nose and '
          'swelling above the eyes, and often kills. It is a controlled disease and horse movement is restricted '
          'in affected areas.',
      actions: [
        'Phone your vet and the state vet now. Keep the horse in a stable at dusk and dawn',
        'Keep the horse cool and quiet, and do not load or transport it',
        'Use insect repellent and keep other horses stabled while midges are active',
        'Vaccinate every year as your vet advises. The vaccine must be given before the season',
      ],
    ),
    // ------------------------------------------------ cattle
    LivestockCondition(
      species: {Species.cattle},
      name: 'Lumpy Skin Disease',
      plainName: 'Lumpy Skin Disease',
      symptomIds: ['skin_nodules', 'fever', 'nasal_discharge', 'eye_discharge', 'milk_drop', 'not_eating'],
      urgency: Urgency.emergency,
      whatItIs:
          'A viral disease spread by biting flies and mosquitoes, causing firm lumps across the skin. '
          'It spreads fastest in warm, wet months.',
      actions: [
        'Call your vet for supportive treatment and antibiotics for secondary infection',
        'Separate affected animals and control flies and ticks',
        'Vaccinate the rest of the herd if your vet advises it',
      ],
    ),
    LivestockCondition(
      species: {Species.cattle, Species.sheep},
      name: 'Blackquarter',
      plainName: 'Blackquarter (Blackleg)',
      symptomIds: ['sudden_death', 'lameness', 'swelling', 'fever', 'stiffness'],
      urgency: Urgency.emergency,
      whatItIs:
          'A soil bacterium that causes gas-filled swelling in heavy muscle, usually in young, well-fed animals. '
          'Death often comes within a day.',
      actions: [
        'Call a vet immediately. An early case can be saved with the right antibiotic',
        'Move the herd off that camp',
        'Vaccinate the rest of the herd every year',
      ],
    ),
    LivestockCondition(
      species: {Species.cattle, Species.goat, Species.sheep},
      name: 'Heartwater',
      plainName: 'Heartwater',
      symptomIds: ['circling', 'fever', 'breathing', 'sudden_death', 'not_eating'],
      urgency: Urgency.emergency,
      whatItIs:
          'Spread by the bont tick. Causes fever then nervous signs: high-stepping, circling and convulsions. '
          'Goats and sheep die very quickly.',
      actions: [
        'Call a vet urgently. Early treatment works',
        'Dip or spray for ticks',
        'Check the whole herd for bont ticks',
      ],
    ),
    LivestockCondition(
      species: {Species.cattle},
      name: 'Redwater',
      plainName: 'Redwater (Babesiosis)',
      symptomIds: ['dark_urine', 'fever', 'pale_gums', 'jaundice', 'not_eating', 'weight_loss'],
      urgency: Urgency.emergency,
      whatItIs:
          'A tick-borne parasite that destroys red blood cells, turning urine red or brown.',
      actions: [
        'Call a vet. It needs a specific injection, and handling stress can kill a sick animal',
        'Keep the animal quiet and in shade, do not drive it',
        'Review your tick control programme',
      ],
    ),
    LivestockCondition(
      species: {Species.cattle},
      name: 'Gallsickness',
      plainName: 'Gallsickness (Anaplasmosis)',
      symptomIds: ['pale_gums', 'jaundice', 'fever', 'weight_loss', 'not_eating'],
      urgency: Urgency.emergency,
      whatItIs:
          'A tick-borne parasite causing severe anaemia and yellow gums. Urine stays normal in colour, '
          'which is how it is told apart from redwater.',
      actions: [
        'Call a vet for treatment',
        'Handle the animal as little as possible',
        'Control ticks across the herd',
      ],
    ),
    LivestockCondition(
      species: {Species.cattle},
      name: 'Three-Day Stiffsickness',
      plainName: 'Three-Day Stiffsickness',
      symptomIds: ['stiffness', 'lameness', 'fever', 'not_eating', 'milk_drop'],
      urgency: Urgency.soon,
      whatItIs:
          'A virus spread by midges. Cattle go stiff and lame for a few days and usually recover on their own.',
      actions: [
        'Provide shade, clean water and soft feed within reach',
        'Ask your vet about anti-inflammatories',
        'Watch animals that go down. They need turning to avoid pressure damage',
      ],
    ),
    // ------------------------------------------------ cattle, goats, sheep
    LivestockCondition(
      species: _ruminants,
      name: 'Mastitis',
      plainName: 'Mastitis',
      symptomIds: ['udder', 'milk_drop', 'fever', 'not_eating', 'weak_young'],
      urgency: Urgency.soon,
      whatItIs:
          'Infection of the udder. Milk turns watery, clotted or blood-stained and the quarter is hot and hard. '
          'Young that suckle from an infected udder go hungry.',
      actions: [
        'Strip the affected quarter out regularly',
        'Get the right treatment from your vet',
        'Milk infected animals last and disinfect teats',
        'Discard milk from treated animals for the full withdrawal period',
      ],
    ),
    LivestockCondition(
      species: _ruminants,
      name: 'Wireworm and Internal Parasites',
      plainName: 'Worms',
      symptomIds: ['weight_loss', 'pale_gums', 'diarrhoea', 'swelling', 'bottle_jaw', 'not_eating'],
      urgency: Urgency.soon,
      whatItIs:
          'Heavy worm burdens cause anaemia, bottle jaw and steady weight loss, worst in young stock after rain. '
          'Worms are now resistant to many dewormers, so guessing wastes money.',
      actions: [
        'Ask your vet for a faecal egg count before dosing the whole herd',
        'Dose only the animals that need it, and rotate the active ingredient on advice',
        'Rest and rotate camps',
      ],
    ),
    LivestockCondition(
      species: _ruminants,
      name: 'Bloat',
      plainName: 'Bloat',
      symptomIds: ['bloat', 'breathing', 'not_eating', 'stiffness'],
      urgency: Urgency.emergency,
      whatItIs:
          'Gas trapped in the rumen swells the left flank. On lush green pasture it can kill within an hour.',
      actions: [
        'Get the animal up and walking',
        'Call a vet immediately if breathing is laboured',
        'Move the herd off lush legume pasture and feed dry roughage first',
      ],
    ),
    LivestockCondition(
      species: _ruminants,
      name: 'Pinkeye',
      plainName: 'Pinkeye',
      symptomIds: ['eye_discharge', 'weight_loss'],
      urgency: Urgency.soon,
      whatItIs:
          'A contagious bacterial eye infection spread by flies and dust. Left alone it can blind the animal.',
      actions: [
        'Treat early with the eye product your vet recommends',
        'Separate affected animals and control flies',
        'Provide shade to reduce glare and dust',
      ],
    ),
    LivestockCondition(
      species: _ruminants,
      name: 'Coccidiosis',
      plainName: 'Coccidiosis (Young Stock Scours)',
      symptomIds: ['diarrhoea', 'weak_young', 'weight_loss', 'not_eating'],
      urgency: Urgency.soon,
      whatItIs:
          'A gut parasite that hits lambs, kids and calves in crowded, damp pens. Scouring, sometimes with blood, '
          'and fast weight loss. Young animals dehydrate quickly.',
      actions: [
        'Give clean water and electrolytes, and keep the animal warm and dry',
        'Call a vet for the right treatment for the whole group',
        'Move young stock to a clean, dry camp and stop feed from being fouled',
      ],
    ),
    LivestockCondition(
      species: {Species.cattle, Species.goat, Species.sheep, Species.horse},
      name: 'Pneumonia',
      plainName: 'Pneumonia',
      symptomIds: ['coughing', 'breathing', 'nasal_discharge', 'fever', 'not_eating', 'depressed'],
      urgency: Urgency.soon,
      whatItIs:
          'Infection of the lungs, often after transport, cold nights or dusty pens. Laboured breathing is a '
          'sign the animal is in trouble and needs a vet the same day.',
      actions: [
        'Separate the animal and give shelter from wind and damp',
        'Call a vet. Antibiotics only work if they suit the germ',
        'If breathing is laboured or the animal will not stand, treat it as urgent',
      ],
    ),
    // ------------------------------------------------ sheep and goats
    LivestockCondition(
      species: _smallStock,
      name: 'Pulpy Kidney',
      plainName: 'Pulpy Kidney (Enterotoxaemia)',
      symptomIds: ['sudden_death', 'circling', 'diarrhoea', 'bloat', 'weak_young'],
      urgency: Urgency.emergency,
      whatItIs:
          'A bacterium that explodes in the gut when animals move quickly onto lush grass or rich feed. The '
          'fastest-growing lambs and kids are found dead or convulsing.',
      actions: [
        'Call a vet at once. Treatment is rarely in time, so prevention matters',
        'Vaccinate the flock or herd with a multi-clostridial vaccine and boost before the rains',
        'Change feed slowly over a week and do not let hungry animals gorge',
      ],
    ),
    LivestockCondition(
      species: _smallStock,
      name: 'Barber\'s Pole Worm',
      plainName: 'Barber\'s Pole Worm (Haemonchus)',
      symptomIds: ['pale_gums', 'bottle_jaw', 'weight_loss', 'not_eating', 'depressed'],
      urgency: Urgency.soon,
      whatItIs:
          'A blood-sucking stomach worm that thrives in warm, wet weather. Animals go pale and weak with a swollen '
          'jaw, often without scouring. It can kill a lamb or kid within days.',
      actions: [
        'Act the same day: check the lower eyelid colour of the whole group',
        'Ask your vet for a faecal egg count and the right dewormer for your farm',
        'Treat only the pale ones, and keep their camp rested',
      ],
    ),
    LivestockCondition(
      species: _smallStock,
      name: 'Orf',
      plainName: 'Orf (Scabby Mouth)',
      symptomIds: ['scabby_lips', 'drooling', 'not_eating', 'weak_young'],
      urgency: Urgency.monitor,
      whatItIs:
          'A virus that makes thick scabs on the lips, nose and sometimes udder. Lambs and kids may refuse to suckle. '
          'It usually clears in 3 to 4 weeks. People can catch it from touching the scabs.',
      actions: [
        'Wear gloves when handling affected animals and wash your hands',
        'Help weak young to feed. Call a vet if they will not eat or the scabs spread',
        'Ask about vaccinating before lambing or kidding',
      ],
    ),
    LivestockCondition(
      species: {Species.sheep, Species.goat, Species.cattle},
      name: 'Bluetongue',
      plainName: 'Bluetongue',
      symptomIds: ['swollen_tongue', 'fever', 'drooling', 'lameness', 'swelling', 'not_eating', 'nasal_discharge'],
      urgency: Urgency.emergency,
      whatItIs:
          'A midge-borne virus in warm, wet months. Sheep get fever, a swollen blue-tinged tongue, a swollen face '
          'and sore feet. Your vet will tell you if it must be reported.',
      actions: [
        'Call your vet today',
        'Keep animals in shade with soft feed and clean water',
        'Vaccinate every year before the midge season',
      ],
    ),
    LivestockCondition(
      species: {Species.sheep, Species.goat},
      name: 'Flystrike',
      plainName: 'Flystrike (Maggots)',
      symptomIds: ['maggots', 'not_eating', 'fever', 'depressed', 'wool_loss'],
      urgency: Urgency.emergency,
      whatItIs:
          'Blowflies lay eggs in dirty wool or a wound and the maggots eat into the flesh. A struck sheep can '
          'die within days.',
      actions: [
        'Get the animal under shade and call a vet the same day',
        'Clip the wool around the area so it can be cleaned',
        'Check the whole flock. Keep tails clean and wounds covered',
      ],
    ),
    LivestockCondition(
      species: {Species.sheep, Species.goat},
      name: 'Footrot',
      plainName: 'Footrot',
      symptomIds: ['foul_hoof', 'lameness', 'swelling', 'not_eating', 'weight_loss'],
      urgency: Urgency.soon,
      whatItIs:
          'A bacterial infection between the toes that spreads in wet camps. Animals graze on their knees and '
          'lose condition. One animal can infect the group.',
      actions: [
        'Trim away rotten horn and treat as your vet shows you',
        'Isolate lame animals and move the flock to a dry camp',
        'Quarantine new animals for two weeks before they join the flock',
      ],
    ),
    LivestockCondition(
      species: _smallStock,
      name: 'Caseous Lymphadenitis',
      plainName: 'Abscess Disease (CLA)',
      symptomIds: ['lymph_lumps', 'weight_loss', 'swelling'],
      urgency: Urgency.monitor,
      whatItIs:
          'Slow abscesses in the lymph glands that burst and spread infection to the camp. Animals look well but '
          'the lumps keep coming back.',
      actions: [
        'Do not squeeze or cut the lump yourself. The pus infects the camp for years',
        'Ask your vet to drain and treat it safely, away from other animals',
        'Cull animals with repeated abscesses on advice. Vaccines exist',
      ],
    ),
    LivestockCondition(
      species: _smallStock,
      name: 'Pregnancy Toxaemia',
      plainName: 'Pregnancy Toxaemia (Twin-Lamb Disease)',
      symptomIds: ['late_pregnancy', 'not_eating', 'depressed', 'circling', 'weight_loss'],
      urgency: Urgency.emergency,
      whatItIs:
          'A heavily pregnant ewe or doe, usually carrying twins, cannot eat enough and her body breaks down fat. '
          'She stands apart, trembles and can go blind or die within days.',
      actions: [
        'Call a vet the same day. Early treatment saves the female',
        'Offer good feed and clean water in small amounts, often',
        'Next season scan for twins and feed late-pregnant females extra',
      ],
    ),
    // ------------------------------------------------ horses
    LivestockCondition(
      species: _horse,
      name: 'Colic',
      plainName: 'Colic',
      symptomIds: ['colic_pain', 'not_eating', 'depressed', 'diarrhoea', 'breathing'],
      urgency: Urgency.emergency,
      whatItIs:
          'Belly pain from the gut. Some cases pass on their own, but a twisted gut kills. A horse that keeps '
          'rolling, sweats or has a swollen belly is an emergency.',
      actions: [
        'Call your vet straight away and take away all feed',
        'Walk the horse gently on soft ground. Do not let it roll violently, and do not leave it alone',
        'Give no drugs unless your vet tells you to',
        'Note the pulse, gum colour and last droppings to tell the vet',
      ],
    ),
    LivestockCondition(
      species: _horse,
      name: 'Laminitis',
      plainName: 'Laminitis (Founder)',
      symptomIds: ['laminitis', 'hoof_heat', 'lameness', 'stiffness', 'depressed'],
      urgency: Urgency.emergency,
      whatItIs:
          'Painful inflammation inside the hooves. It often follows rich spring grass, a feed binge or a heavy fever. '
          'Without quick treatment the bone in the hoof can rotate.',
      actions: [
        'Call a vet the same day',
        'Take the horse off grass and rich feed, and give it a deep soft bed',
        'Do not force it to walk. Cold water on the hooves can ease pain until the vet comes',
      ],
    ),
    LivestockCondition(
      species: _horse,
      name: 'Strangles',
      plainName: 'Strangles',
      symptomIds: ['lump_throat', 'nasal_discharge', 'fever', 'coughing', 'not_eating', 'depressed'],
      urgency: Urgency.soon,
      whatItIs:
          'A very contagious bacterial infection that makes the glands under the jaw swell and burst. '
          'It spreads between horses on hands, buckets and tack.',
      actions: [
        'Isolate the horse and anything it touches. Wash your hands between horses',
        'Call a vet to confirm and decide on treatment',
        'Keep new or visiting horses away until the outbreak is over and the vet says it is safe',
      ],
    ),
    LivestockCondition(
      species: _horse,
      name: 'Equine Influenza',
      plainName: 'Horse Flu',
      symptomIds: ['coughing', 'nasal_discharge', 'fever', 'not_eating', 'depressed'],
      urgency: Urgency.soon,
      whatItIs:
          'A fast-spreading virus causing a dry cough, fever and runny nose. Horses need rest or they can '
          'get pneumonia.',
      actions: [
        'Rest the horse for several weeks and keep it in clean air',
        'Isolate sick horses and call a vet for fever above 38.5 C',
        'Keep vaccinations up to date',
      ],
    ),
    LivestockCondition(
      species: _horse,
      name: 'Equine Piroplasmosis',
      plainName: 'Biliary (Horse Tick Fever)',
      symptomIds: ['jaundice', 'pale_gums', 'dark_urine', 'fever', 'not_eating', 'depressed'],
      urgency: Urgency.emergency,
      whatItIs:
          'A tick-borne parasite that destroys red blood cells. The horse is feverish, off its food and shows '
          'yellow or pale gums and sometimes dark urine.',
      actions: [
        'Call a vet urgently. Treatment is time-sensitive',
        'Keep the horse still and in shade',
        'Check for ticks daily and use a tick control programme',
      ],
    ),
    LivestockCondition(
      species: _horse,
      name: 'Tetanus',
      plainName: 'Tetanus',
      symptomIds: ['muscle_spasm', 'stiffness', 'lameness', 'not_eating', 'depressed'],
      urgency: Urgency.emergency,
      whatItIs:
          'Soil bacteria enter a deep wound or hoof puncture and make the muscles lock. The horse stands stiff like '
          'a rocking horse with a stiff jaw and the third eyelid across the eye. It is often fatal.',
      actions: [
        'Call a vet immediately and keep the horse in a dark, quiet stable',
        'Do not handle roughly. Noise and touch set off spasms',
        'Vaccinate every horse against tetanus, and boost after wounds',
      ],
    ),
    LivestockCondition(
      species: _horse,
      name: 'Hoof Abscess',
      plainName: 'Hoof Abscess',
      symptomIds: ['hoof_heat', 'lameness', 'swelling', 'depressed'],
      urgency: Urgency.soon,
      whatItIs:
          'Pus trapped in the hoof makes a horse suddenly very lame on one leg, with heat in the foot and a strong pulse.',
      actions: [
        'Call your vet or farrier to find and drain it',
        'Keep the hoof clean and dry, and soak it as shown',
        'Check the tetanus vaccination is up to date',
      ],
    ),
    LivestockCondition(
      species: _horse,
      name: 'Horse Worms',
      plainName: 'Worms',
      symptomIds: ['weight_loss', 'diarrhoea', 'colic_pain', 'pale_gums', 'not_eating'],
      urgency: Urgency.soon,
      whatItIs:
          'Heavy worm burdens cause poor condition, a dull coat, loose droppings and colic. Over-dosing breeds '
          'resistant worms.',
      actions: [
        'Ask your vet for a faecal egg count and dose according to the result',
        'Pick up droppings from paddocks often and rest camps',
        'Treat young horses as the most at risk',
      ],
    ),
    LivestockCondition(
      species: _horse,
      name: 'Sweet Itch',
      plainName: 'Sweet Itch',
      symptomIds: ['itchy_mane'],
      urgency: Urgency.monitor,
      whatItIs:
          'An allergy to midge bites. The horse rubs its mane and tail raw in the warm months and the skin thickens.',
      actions: [
        'Stable the horse at dusk and dawn when midges bite',
        'Use a midge rug and repellent, and keep the horse away from water',
        'Ask your vet if the skin is broken or infected',
      ],
    ),
  ];

  /// The signs a farmer may tick for [species].
  static List<Symptom> symptomsFor(Species species) =>
      [for (final s in symptoms) if (s.appliesTo(species)) s];

  /// The conditions that can affect [species].
  static List<LivestockCondition> conditionsFor(Species species) =>
      [for (final c in conditions) if (c.species.contains(species)) c];

  /// Ranks conditions by symptom overlap, for [species] when given.
  ///
  /// Notifiable diseases carry a deliberate weighting: missing an FMD or anthrax
  /// case is far more costly than showing it and being wrong.
  static List<ConditionMatch> match(Set<String> selected, {Species? species}) {
    if (selected.isEmpty) return const [];

    final matches = <ConditionMatch>[];
    for (final c in species == null ? conditions : conditionsFor(species)) {
      final hits = c.symptomIds.where(selected.contains).length;
      if (hits == 0) continue;

      final coverage = hits / c.symptomIds.length;
      final relevance = hits / selected.length;
      var score = (coverage * 0.45) + (relevance * 0.55);
      if (c.urgency == Urgency.notifiable) score *= 1.25;

      matches.add(ConditionMatch(c, score.clamp(0.0, 1.0)));
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches.take(4).toList();
  }
}
