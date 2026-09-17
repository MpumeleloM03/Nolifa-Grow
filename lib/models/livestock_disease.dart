/// Symptom-led reference for South African cattle conditions.
///
/// This is deliberately not a diagnosis. Several of these are controlled
/// diseases under the Animal Diseases Act 35 of 1984, where the legally correct
/// action is to call the state veterinarian rather than treat on farm — so the
/// matcher is tuned to surface those first even on a weak symptom match.
class Symptom {
  final String id;
  final String label;
  final String group;

  const Symptom(this.id, this.label, this.group);
}

enum Urgency {
  notifiable('Call the state vet now', 'This is a controlled disease. By law you must report it.'),
  emergency('Urgent — same day', 'Get a vet out today. Animals can die quickly.'),
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

  const LivestockCondition({
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
    Symptom('blisters_mouth', 'Blisters or sores in the mouth', 'Mouth & feet'),
    Symptom('drooling', 'Drooling / stringy saliva', 'Mouth & feet'),
    Symptom('blisters_feet', 'Blisters between the hooves', 'Mouth & feet'),
    Symptom('lameness', 'Limping or unwilling to walk', 'Mouth & feet'),
    Symptom('not_eating', 'Off feed / not grazing', 'General'),
    Symptom('fever', 'Fever, hot ears and nose', 'General'),
    Symptom('sudden_death', 'Sudden death with no warning', 'General'),
    Symptom('weight_loss', 'Losing condition over weeks', 'General'),
    Symptom('stiffness', 'Stiff, moving with difficulty', 'General'),
    Symptom('skin_nodules', 'Hard lumps or nodules on the skin', 'Skin'),
    Symptom('swelling', 'Swelling under the skin', 'Skin'),
    Symptom('eye_discharge', 'Weeping or cloudy eye', 'Head'),
    Symptom('nasal_discharge', 'Runny nose', 'Head'),
    Symptom('coughing', 'Coughing', 'Chest'),
    Symptom('breathing', 'Laboured breathing', 'Chest'),
    Symptom('diarrhoea', 'Scouring / diarrhoea', 'Gut'),
    Symptom('bloat', 'Swollen left flank (bloat)', 'Gut'),
    Symptom('dark_urine', 'Red or dark urine', 'Blood'),
    Symptom('pale_gums', 'Pale gums and eyelids', 'Blood'),
    Symptom('jaundice', 'Yellow gums or eyes', 'Blood'),
    Symptom('abortion', 'Cow aborted / lost calf', 'Breeding'),
    Symptom('udder', 'Hot, hard or swollen udder', 'Breeding'),
    Symptom('milk_drop', 'Sudden drop in milk', 'Breeding'),
    Symptom('circling', 'Circling, pressing head, odd behaviour', 'Nerves'),
  ];

  static const conditions = <LivestockCondition>[
    LivestockCondition(
      name: 'Foot-and-Mouth Disease',
      plainName: 'Foot-and-Mouth — Report Immediately',
      symptomIds: ['blisters_mouth', 'drooling', 'blisters_feet', 'lameness', 'fever', 'not_eating', 'milk_drop'],
      urgency: Urgency.notifiable,
      whatItIs:
          'A highly contagious virus that spreads through a herd and to neighbouring farms very fast. '
          'It is a controlled disease in South Africa and outbreaks trigger movement bans.',
      actions: [
        'Stop all animal movement on and off the farm immediately',
        'Phone your state veterinarian today — this is a legal duty',
        'Keep sick animals away from the rest of the herd',
        'Do not visit other farms, and disinfect boots and vehicle tyres',
      ],
    ),
    LivestockCondition(
      name: 'Anthrax',
      plainName: 'Possible Anthrax — Do Not Open the Carcass',
      symptomIds: ['sudden_death', 'fever', 'swelling', 'not_eating'],
      urgency: Urgency.notifiable,
      whatItIs:
          'A bacterial disease that usually shows as sudden death, often with dark blood from the nose or anus. '
          'It is dangerous to people and is a controlled disease.',
      actions: [
        'Do NOT cut open or skin the carcass — this spreads spores that last decades',
        'Phone your state veterinarian immediately',
        'Keep people and other animals away from the carcass',
        'Wash thoroughly if you touched the animal',
      ],
    ),
    LivestockCondition(
      name: 'Brucellosis',
      plainName: 'Possible Contagious Abortion',
      symptomIds: ['abortion', 'swelling', 'weight_loss'],
      urgency: Urgency.notifiable,
      whatItIs:
          'A bacterial disease causing abortion in the last third of pregnancy. '
          'It infects people too, and is a controlled disease requiring testing.',
      actions: [
        'Do not handle the aborted calf or afterbirth with bare hands',
        'Phone your state vet to arrange blood testing of the herd',
        'Isolate the cow that aborted',
        'Do not drink unpasteurised milk from the herd',
      ],
    ),
    LivestockCondition(
      name: 'Lumpy Skin Disease',
      plainName: 'Lumpy Skin Disease',
      symptomIds: ['skin_nodules', 'fever', 'nasal_discharge', 'eye_discharge', 'milk_drop', 'not_eating'],
      urgency: Urgency.emergency,
      whatItIs:
          'A viral disease spread by biting flies and mosquitoes, causing firm lumps across the skin. '
          'It spreads fastest in warm, wet months.',
      actions: [
        'Call your vet — supportive treatment and antibiotics for secondary infection',
        'Separate affected animals and control flies and ticks',
        'Vaccinate the rest of the herd if your vet advises it',
      ],
    ),
    LivestockCondition(
      name: 'Blackquarter',
      plainName: 'Blackquarter (Blackleg)',
      symptomIds: ['sudden_death', 'lameness', 'swelling', 'fever', 'stiffness'],
      urgency: Urgency.emergency,
      whatItIs:
          'A soil bacterium that causes gas-filled swelling in heavy muscle, usually in young, well-fed cattle. '
          'Death often comes within a day.',
      actions: [
        'Call a vet immediately — high-dose penicillin can save an early case',
        'Move the herd off that camp',
        'Vaccinate the rest of the herd annually',
      ],
    ),
    LivestockCondition(
      name: 'Heartwater',
      plainName: 'Heartwater',
      symptomIds: ['circling', 'fever', 'breathing', 'sudden_death', 'not_eating'],
      urgency: Urgency.emergency,
      whatItIs:
          'Spread by the bont tick. Causes fever then nervous signs — high-stepping, circling and convulsions.',
      actions: [
        'Call a vet urgently — early tetracycline treatment works',
        'Dip or spray for ticks',
        'Check the whole herd for bont ticks',
      ],
    ),
    LivestockCondition(
      name: 'Redwater',
      plainName: 'Redwater (Babesiosis)',
      symptomIds: ['dark_urine', 'fever', 'pale_gums', 'jaundice', 'not_eating', 'weight_loss'],
      urgency: Urgency.emergency,
      whatItIs:
          'A tick-borne parasite that destroys red blood cells, turning urine red or brown.',
      actions: [
        'Call a vet — needs a specific injection, and handling stress can kill a sick animal',
        'Keep the animal quiet and in shade, do not drive it',
        'Review your tick control programme',
      ],
    ),
    LivestockCondition(
      name: 'Gallsickness',
      plainName: 'Gallsickness (Anaplasmosis)',
      symptomIds: ['pale_gums', 'jaundice', 'fever', 'weight_loss', 'not_eating'],
      urgency: Urgency.emergency,
      whatItIs:
          'A tick-borne parasite causing severe anaemia and yellow gums. Urine stays normal in colour, '
          'which is how it is told apart from redwater.',
      actions: [
        'Call a vet for tetracycline treatment',
        'Handle the animal as little as possible',
        'Control ticks across the herd',
      ],
    ),
    LivestockCondition(
      name: 'Three-Day Stiffsickness',
      plainName: 'Three-Day Stiffsickness',
      symptomIds: ['stiffness', 'lameness', 'fever', 'not_eating', 'milk_drop'],
      urgency: Urgency.soon,
      whatItIs:
          'A virus spread by midges. Cattle go stiff and lame for a few days and usually recover on their own.',
      actions: [
        'Provide shade, clean water and soft feed within reach',
        'Ask your vet about anti-inflammatories',
        'Watch animals that go down — they need turning to avoid pressure damage',
      ],
    ),
    LivestockCondition(
      name: 'Mastitis',
      plainName: 'Mastitis',
      symptomIds: ['udder', 'milk_drop', 'fever', 'not_eating'],
      urgency: Urgency.soon,
      whatItIs:
          'Infection of the udder. Milk turns watery, clotted or blood-stained and the quarter is hot and hard.',
      actions: [
        'Strip the affected quarter out regularly',
        'Get the right intramammary treatment from your vet',
        'Milk infected cows last and disinfect teats',
        'Discard milk from treated cows for the full withdrawal period',
      ],
    ),
    LivestockCondition(
      name: 'Wireworm and Internal Parasites',
      plainName: 'Worms',
      symptomIds: ['weight_loss', 'pale_gums', 'diarrhoea', 'swelling', 'not_eating'],
      urgency: Urgency.soon,
      whatItIs:
          'Heavy worm burdens cause anaemia, bottle jaw and steady weight loss, worst in young stock after rain.',
      actions: [
        'Dose with an appropriate remedy — rotate the active ingredient',
        'Ask your vet for a faecal egg count before dosing the whole herd',
        'Rest and rotate camps',
      ],
    ),
    LivestockCondition(
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
      name: 'Bovine Tuberculosis',
      plainName: 'Possible Bovine TB',
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
  ];

  /// Ranks conditions by symptom overlap.
  ///
  /// Notifiable diseases carry a deliberate weighting: missing an FMD or anthrax
  /// case is far more costly than showing it and being wrong.
  static List<ConditionMatch> match(Set<String> selected) {
    if (selected.isEmpty) return const [];

    final matches = <ConditionMatch>[];
    for (final c in conditions) {
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
