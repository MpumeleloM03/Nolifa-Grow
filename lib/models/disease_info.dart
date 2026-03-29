class DiseaseInfo {
  final String name;
  final String plainName;
  final String description;
  final String severity;
  final String severityColor;
  final List<String> treatment;
  final String homRemedy;

  const DiseaseInfo({
    required this.name,
    required this.plainName,
    required this.description,
    required this.severity,
    required this.severityColor,
    required this.treatment,
    required this.homRemedy,
  });
}

class DiseaseDatabase {
  static const Map<String, DiseaseInfo> diseases = {
    'Healthy': DiseaseInfo(
      name: 'Healthy',
      plainName: 'Your plant looks healthy',
      description:
          'No disease or damage was detected on this plant. Keep doing what you are doing.',
      severity: 'No action needed',
      severityColor: 'green',
      treatment: [
        'Continue your current watering routine',
        'Make sure the plant gets enough sunlight',
        'Check again in 7 days',
      ],
      homRemedy: 'No treatment needed.',
    ),
    'Early_Blight': DiseaseInfo(
      name: 'Early_Blight',
      plainName: 'Early Blight — Fungal Infection',
      description:
          'Your plant has a fungal disease that starts on older lower leaves and spreads upward. Dark brown spots with yellow rings appear on the leaves.',
      severity: 'Act soon — this spreads if untreated',
      severityColor: 'orange',
      treatment: [
        'Remove all affected leaves immediately and throw them away — do not compost them',
        'Buy a copper-based fungicide from your nearest garden or hardware store',
        'Spray the whole plant in the evening, not in direct sunlight',
        'Repeat spraying every 7 days until leaves look healthy',
        'Water at the base of the plant — avoid wetting the leaves',
      ],
      homRemedy:
          'No fungicide available? Mix 1 tablespoon of baking soda with 1 litre of water and a few drops of dish soap. Spray on affected leaves every 3 days.',
    ),
    'Late_Blight': DiseaseInfo(
      name: 'Late_Blight',
      plainName: 'Late Blight — Serious Fungal Disease',
      description:
          'This is a serious disease that can destroy your entire crop quickly. Dark water-soaked patches appear on leaves and stems. White mold may be visible underneath leaves.',
      severity: 'Urgent — act immediately',
      severityColor: 'red',
      treatment: [
        'Remove and destroy all heavily infected plants immediately',
        'Do not compost infected material — burn it or bag it for waste',
        'Buy a fungicide containing chlorothalonil or mancozeb',
        'Spray all remaining plants thoroughly',
        'Spray every 5 days until no new symptoms appear',
        'Avoid working with plants when they are wet',
      ],
      homRemedy:
          'No fungicide available? Remove infected parts immediately and spray remaining plants with a mixture of 1 tablespoon copper sulphate dissolved in 10 litres of water.',
    ),
    'Leaf_Miner': DiseaseInfo(
      name: 'Leaf_Miner',
      plainName: 'Leaf Miner — Insect Damage',
      description:
          'Tiny insects are tunneling inside your leaves leaving winding white or yellow trails. This weakens the plant and reduces its ability to absorb sunlight.',
      severity: 'Monitor — catch it early',
      severityColor: 'orange',
      treatment: [
        'Remove and destroy heavily mined leaves',
        'Buy a spinosad-based insecticide from your garden store',
        'Spray the plant focusing on the underside of leaves where eggs are laid',
        'Repeat every 7 to 10 days',
        'Yellow sticky traps placed near plants can catch adult flies',
      ],
      homRemedy:
          'No insecticide available? Spray leaves with neem oil mixed with water — 2 tablespoons per litre. Focus on the underside of leaves. Repeat every 5 days.',
    ),
    'nutrient deficiency': DiseaseInfo(
      name: 'nutrient deficiency',
      plainName: 'Nutrient Deficiency — Your Plant Needs Feeding',
      description:
          'Your plant is not getting enough nutrients from the soil. This causes yellowing leaves, stunted growth, and poor fruit production.',
      severity: 'Act soon — plant is weakening',
      severityColor: 'orange',
      treatment: [
        'Buy a balanced fertiliser — look for NPK on the label at any garden store',
        'Apply fertiliser to moist soil — never dry soil as it can burn roots',
        'For yellowing leaves specifically add nitrogen — look for urea or ammonium nitrate',
        'For purple leaves add phosphorus fertiliser',
        'For brown leaf edges add potassium fertiliser',
        'Re-apply every 2 to 4 weeks during growing season',
      ],
      homRemedy:
          'No fertiliser available? Compost tea works well — soak compost in water for 24 hours and water your plant with the liquid. Banana peels buried near roots add potassium.',
    ),
    'powdery mildew': DiseaseInfo(
      name: 'powdery mildew',
      plainName: 'Powdery Mildew — White Fungal Coating',
      description:
          'A white or grey powdery coating is appearing on your leaves. This is a fungal disease that thrives in warm dry conditions and spreads quickly.',
      severity: 'Act soon — this spreads if untreated',
      severityColor: 'orange',
      treatment: [
        'Remove heavily affected leaves immediately',
        'Improve airflow around your plant by pruning crowded branches',
        'Buy a sulphur-based fungicide or potassium bicarbonate spray',
        'Spray all affected areas thoroughly',
        'Repeat every 7 days until no new growth appears',
        'Avoid overhead watering — water at the base only',
      ],
      homRemedy:
          'Mix 1 tablespoon of baking soda and half a teaspoon of dish soap in 1 litre of water. Spray on affected leaves every 3 days. This works well for mild cases.',
    ),
    'rust': DiseaseInfo(
      name: 'rust',
      plainName: 'Rust Disease — Orange Fungal Spots',
      description:
          'Orange, yellow or brown powdery spots are appearing on your leaves. This is a fungal disease that spreads through the air and worsens in wet weather.',
      severity: 'Act soon — this spreads if untreated',
      severityColor: 'orange',
      treatment: [
        'Remove and destroy all infected leaves — do not compost them',
        'Buy a fungicide containing myclobutanil or tebuconazole',
        'Spray the whole plant including the underside of leaves',
        'Repeat every 7 to 14 days',
        'Avoid wetting leaves when watering',
      ],
      homRemedy:
          'No fungicide available? Mix 1 tablespoon of baking soda with 1 litre of water and spray on affected areas every 3 days. Remove badly affected leaves by hand.',
    ),
    'leaf spot': DiseaseInfo(
      name: 'leaf spot',
      plainName: 'Leaf Spot — Fungal or Bacterial Spots',
      description:
          'Dark or water-soaked spots are appearing on your leaves. These can be caused by fungi or bacteria and spread through water splash and wind.',
      severity: 'Monitor — treat before it spreads',
      severityColor: 'orange',
      treatment: [
        'Remove affected leaves and dispose of them away from your garden',
        'Avoid watering from above — water at the base of the plant',
        'Buy a copper-based fungicide from your garden store',
        'Spray the entire plant focusing on new growth',
        'Repeat every 10 days',
      ],
      homRemedy:
          'Spray with a mixture of 1 teaspoon of baking soda and a few drops of dish soap in 1 litre of water. Apply every 3 to 5 days on affected leaves.',
    ),
    'mosaic virus': DiseaseInfo(
      name: 'mosaic virus',
      plainName: 'Mosaic Virus — Viral Infection',
      description:
          'Your plant has a viral infection showing as patchy yellow and green mottled patterns on the leaves. This disease is spread by insects especially aphids and has no cure.',
      severity: 'Urgent — remove infected plants',
      severityColor: 'red',
      treatment: [
        'Remove and destroy infected plants immediately to protect others nearby',
        'Do not compost infected material',
        'Control aphids on remaining plants using insecticide — they spread this virus',
        'Wash your hands and tools after handling infected plants',
        'Plant virus-resistant varieties next season',
      ],
      homRemedy:
          'No chemical control exists for the virus itself. Focus on controlling aphids with neem oil spray — 2 tablespoons per litre of water. Spray every 5 days.',
    ),
    'alternaria': DiseaseInfo(
      name: 'alternaria',
      plainName: 'Alternaria — Fungal Leaf Disease',
      description:
          'Dark brown or black spots with yellow halos are appearing on your leaves. This fungal disease spreads in warm wet conditions and can affect fruits as well.',
      severity: 'Act soon — this spreads if untreated',
      severityColor: 'orange',
      treatment: [
        'Remove all affected leaves and dispose of them',
        'Buy a fungicide containing chlorothalonil or mancozeb',
        'Spray the whole plant in the evening',
        'Repeat every 7 to 10 days',
        'Improve airflow around plants by pruning',
        'Avoid overhead watering',
      ],
      homRemedy:
          'Spray with baking soda solution — 1 tablespoon per litre of water with a few drops of dish soap. Apply every 3 days on affected areas.',
    ),
    'bacterial infection': DiseaseInfo(
      name: 'bacterial infection',
      plainName: 'Bacterial Infection Detected',
      description:
          'Your plant has a bacterial infection. Bacteria cause water-soaked spots, yellowing leaves, and rotting tissue. It spreads quickly in wet conditions and through contaminated tools.',
      severity: 'Act soon — this spreads if untreated',
      severityColor: 'red',
      treatment: [
        'Remove all infected leaves and stems immediately',
        'Dispose of infected material — do not compost it',
        'Buy a copper-based bactericide from your garden store',
        'Spray the whole plant thoroughly including stems',
        'Avoid wetting leaves when watering — water at the base only',
        'Disinfect your tools with diluted bleach after use',
        'Repeat spray every 7 days until symptoms stop',
      ],
      homRemedy:
          'No bactericide available? Spray with a mixture of 1 tablespoon of copper sulphate dissolved in 10 litres of water. Apply every 5 days. Remove badly infected parts by hand.',
    ),
    'fungal infection': DiseaseInfo(
      name: 'fungal infection',
      plainName: 'Fungal Infection Detected',
      description:
          'Your plant has a fungal infection. Fungi spread through spores carried by wind and water. They thrive in warm humid conditions and can spread to nearby plants quickly.',
      severity: 'Act soon — this spreads if untreated',
      severityColor: 'orange',
      treatment: [
        'Remove all visibly infected leaves and dispose of them away from your garden',
        'Buy a broad-spectrum fungicide from your garden or hardware store',
        'Spray the whole plant in the evening when it is cooler',
        'Focus on the underside of leaves where spores hide',
        'Repeat every 7 days until no new symptoms appear',
        'Improve airflow around the plant by pruning crowded branches',
      ],
      homRemedy:
          'No fungicide available? Mix 1 tablespoon of baking soda and a few drops of dish soap in 1 litre of water. Spray every 3 days on all affected areas.',
    ),
    'aphids': DiseaseInfo(
      name: 'aphids',
      plainName: 'Aphid Infestation — Insect Attack',
      description:
          'Tiny soft-bodied insects are feeding on your plant sap. Aphids cluster on new growth and the underside of leaves causing curling, yellowing, and stunted growth. They also spread viral diseases between plants.',
      severity: 'Act soon — colonies grow quickly',
      severityColor: 'orange',
      treatment: [
        'Check the underside of leaves for clusters of tiny green, black, or white insects',
        'Spray plants with a strong stream of water to knock aphids off',
        'Buy an insecticidal soap or neem oil spray from your garden store',
        'Spray the entire plant focusing on new growth and leaf undersides',
        'Repeat every 5 to 7 days until no aphids are visible',
        'Introduce ladybirds to your garden — they eat aphids naturally',
      ],
      homRemedy:
          'Mix 1 tablespoon of dish soap with 1 litre of water. Spray directly on aphid colonies every 2 to 3 days. The soap breaks down their protective coating.',
    ),
    'whitefly': DiseaseInfo(
      name: 'whitefly',
      plainName: 'Whitefly — Flying Insect Pest',
      description:
          'Tiny white flying insects are attacking your plant. Whiteflies feed on plant sap from the underside of leaves causing yellowing and wilting. They also produce sticky honeydew that leads to black sooty mould.',
      severity: 'Act soon — spreads to nearby plants',
      severityColor: 'orange',
      treatment: [
        'Shake the plant gently — whiteflies will fly up in a cloud if present',
        'Buy yellow sticky traps from your garden store and hang them near affected plants',
        'Spray with insecticidal soap or neem oil focusing on leaf undersides',
        'Remove heavily infested leaves',
        'Repeat spraying every 5 days for 3 weeks',
      ],
      homRemedy:
          'Spray with a mixture of 1 tablespoon dish soap and 1 litre of water on leaf undersides every 3 days. Yellow sticky cards made from yellow cardboard coated in petroleum jelly also trap adults.',
    ),
    'root rot': DiseaseInfo(
      name: 'root rot',
      plainName: 'Root Rot — Overwatering Damage',
      description:
          'Your plant roots are rotting due to waterlogged soil. This is usually caused by overwatering or poor drainage. Symptoms include yellowing leaves, wilting despite wet soil, and brown mushy roots.',
      severity: 'Urgent — plant may not survive if untreated',
      severityColor: 'red',
      treatment: [
        'Stop watering immediately',
        'Remove the plant from its pot or dig it up carefully',
        'Inspect the roots — healthy roots are white and firm, rotten roots are brown and mushy',
        'Cut away all rotten roots with clean scissors',
        'Allow roots to dry for a few hours',
        'Replant in fresh well-draining soil',
        'Water sparingly going forward — only when the top 5cm of soil is dry',
      ],
      homRemedy:
          'No fungicide available? Dust the trimmed roots with cinnamon powder before replanting — it has natural antifungal properties. Ensure the new pot or planting area has good drainage.',
    ),
    'sunburn': DiseaseInfo(
      name: 'sunburn',
      plainName: 'Sun Damage — Too Much Direct Sunlight',
      description:
          'Your plant has been damaged by excessive direct sunlight. Bleached white or brown crispy patches appear on leaves that face the sun directly. This is not a disease and will not spread.',
      severity: 'Monitor — move plant if possible',
      severityColor: 'orange',
      treatment: [
        'Move potted plants to a location with indirect or filtered light',
        'For garden plants create shade using 30 to 50 percent shade cloth',
        'Remove severely damaged leaves',
        'Water more frequently during hot periods — morning watering is best',
        'New growth will be healthy once the plant is in a better position',
      ],
      homRemedy:
          'No shade cloth available? Use an old bedsheet or hessian bag to create temporary shade during the hottest part of the day between 11am and 3pm.',
    ),
    'spider mites': DiseaseInfo(
      name: 'spider mites',
      plainName: 'Spider Mites — Tiny Arachnid Pest',
      description:
          'Microscopic spider mites are feeding on your plant. Look for fine webbing on leaves and stems, and tiny yellow or white speckles on leaf surfaces. They thrive in hot dry conditions.',
      severity: 'Act soon — spreads rapidly in dry weather',
      severityColor: 'orange',
      treatment: [
        'Look for fine webbing between leaves and stems to confirm spider mites',
        'Spray the entire plant with water — spider mites hate moisture',
        'Buy a miticide or neem oil spray from your garden store',
        'Spray every 3 days for 2 weeks focusing on leaf undersides',
        'Increase humidity around the plant by misting regularly',
        'Remove heavily infested leaves',
      ],
      homRemedy:
          'Mix 2 tablespoons of neem oil with 1 litre of water and a few drops of dish soap. Spray every 3 days. Alternatively wipe leaves with a damp cloth to physically remove mites.',
    ),
    'downy mildew': DiseaseInfo(
      name: 'downy mildew',
      plainName: 'Downy Mildew — Fungal Disease',
      description:
          'A fungal disease causing yellow patches on the top of leaves with grey or purple fuzzy growth on the underside. It spreads rapidly in cool wet conditions and can destroy crops quickly.',
      severity: 'Act soon — spreads fast in wet weather',
      severityColor: 'orange',
      treatment: [
        'Remove all infected leaves immediately',
        'Improve airflow by pruning crowded growth',
        'Buy a fungicide containing copper or chlorothalonil',
        'Spray the whole plant including leaf undersides',
        'Avoid overhead watering — water at the base only',
        'Repeat every 7 days until symptoms stop',
      ],
      homRemedy:
          'Spray with a copper sulphate solution — 1 tablespoon per 10 litres of water. Apply every 5 days. Remove badly affected leaves by hand immediately.',
    ),
    'botrytis': DiseaseInfo(
      name: 'botrytis',
      plainName: 'Grey Mould — Botrytis Fungal Disease',
      description:
          'Grey fuzzy mould is growing on your plant leaves, stems, or fruits. Botrytis thrives in cool humid conditions and spreads through the air. It can rapidly destroy flowers and fruits.',
      severity: 'Urgent — spreads very quickly',
      severityColor: 'red',
      treatment: [
        'Remove all infected plant material immediately — bag it and dispose of it',
        'Do not compost infected material',
        'Improve airflow around plants by pruning and spacing',
        'Reduce humidity — avoid wetting leaves when watering',
        'Buy a fungicide containing iprodione or chlorothalonil',
        'Spray every 7 days until clear',
      ],
      homRemedy:
          'No fungicide available? Remove all affected parts immediately and dust remaining healthy tissue with bicarbonate of soda. Improve ventilation as much as possible.',
    ),
    'grey leaf spot': DiseaseInfo(
      name: 'grey leaf spot',
      plainName: 'Grey Leaf Spot — Common Maize Disease',
      description:
          'Grey or tan rectangular lesions are appearing on your maize leaves running parallel to the leaf veins. This is one of the most common and damaging maize diseases in KwaZulu-Natal.',
      severity: 'Act soon — can cause major yield loss',
      severityColor: 'orange',
      treatment: [
        'Remove and destroy severely infected leaves',
        'Buy a fungicide containing azoxystrobin or propiconazole from your agridealer',
        'Spray at first sign of infection and repeat every 14 days',
        'Plant resistant maize varieties next season',
        'Rotate crops — do not plant maize in the same spot every year',
        'Avoid planting in areas with poor drainage',
      ],
      homRemedy:
          'No fungicide available? Remove infected leaves and improve airflow around plants. Crop rotation next season is the best long-term prevention.',
    ),
    'maize streak virus': DiseaseInfo(
      name: 'maize streak virus',
      plainName: 'Maize Streak Virus — Viral Disease',
      description:
          'Yellow streaks or stripes are running along your maize leaves. This viral disease is spread by leafhoppers and is very common in KwaZulu-Natal. There is no cure once a plant is infected.',
      severity: 'Urgent — remove infected plants',
      severityColor: 'red',
      treatment: [
        'Remove and destroy all infected maize plants immediately',
        'Do not compost infected material',
        'Control leafhopper insects with insecticide — they spread this virus',
        'Plant maize streak resistant varieties next season — ask your agridealer for MSV resistant seed',
        'Plant early in the season before leafhopper populations peak',
        'Keep weeds down around your maize — leafhoppers breed in weeds',
      ],
      homRemedy:
          'No insecticide available? Spray neem oil solution on remaining healthy plants to repel leafhoppers — 2 tablespoons per litre of water every 5 days.',
    ),
    'northern leaf blight': DiseaseInfo(
      name: 'northern leaf blight',
      plainName: 'Northern Leaf Blight — Maize Fungal Disease',
      description:
          'Large grey-green or tan cigar-shaped lesions are appearing on your maize leaves. This fungal disease spreads rapidly in cool wet weather and can cause serious yield loss.',
      severity: 'Act soon — spreads quickly in wet conditions',
      severityColor: 'orange',
      treatment: [
        'Remove heavily infected leaves',
        'Buy a fungicide containing mancozeb or azoxystrobin from your agridealer',
        'Spray at first sign and repeat every 14 days during wet weather',
        'Plant resistant varieties next season',
        'Rotate crops annually',
        'Remove crop residue after harvest — fungal spores survive in old plant material',
      ],
      homRemedy:
          'No fungicide available? Remove infected leaves and ensure good spacing between plants for airflow. Mancozeb is widely available and affordable at most agridealers.',
    ),
    'fusarium wilt': DiseaseInfo(
      name: 'fusarium wilt',
      plainName: 'Fusarium Wilt — Soil Fungal Disease',
      description:
          'Your plant is wilting from the bottom up even when the soil is moist. Leaves turn yellow then brown starting on one side of the plant. When you cut the stem you may see brown discolouration inside. This soil-borne fungal disease has no cure.',
      severity: 'Urgent — remove infected plants',
      severityColor: 'red',
      treatment: [
        'Remove and destroy infected plants immediately — do not compost them',
        'Do not replant the same crop in that soil for at least 3 years',
        'Solarise the soil — cover with clear plastic for 4 to 6 weeks in summer to kill fungus with heat',
        'Plant resistant varieties next season — ask your agridealer',
        'Improve soil drainage',
        'Avoid injuring roots when transplanting or weeding',
      ],
      homRemedy:
          'No chemical control is effective for fusarium wilt once established. Soil solarisation using clear plastic sheeting in summer is the most accessible treatment without chemicals.',
    ),
    'black rot': DiseaseInfo(
      name: 'black rot',
      plainName: 'Black Rot — Cabbage Bacterial Disease',
      description:
          'Yellow V-shaped lesions are appearing at the edges of your cabbage or brassica leaves pointing toward the centre. The veins inside the leaf turn black. This bacterial disease spreads through water splash and contaminated tools.',
      severity: 'Act soon — spreads through the whole crop',
      severityColor: 'orange',
      treatment: [
        'Remove all infected leaves immediately',
        'Disinfect tools with diluted bleach between plants',
        'Avoid overhead watering',
        'Buy a copper-based bactericide and spray every 7 days',
        'Do not replant brassicas in the same spot for 2 years',
        'Buy certified disease-free seed next season',
      ],
      homRemedy:
          'Spray with copper sulphate solution — 1 tablespoon per 10 litres of water every 5 days. Remove infected leaves immediately and avoid working with wet plants.',
    ),
    'bean rust': DiseaseInfo(
      name: 'bean rust',
      plainName: 'Bean Rust — Fungal Disease',
      description:
          'Reddish-brown powdery pustules are appearing on the underside of your bean leaves with corresponding yellow spots on the top. This fungal disease is very common in KwaZulu-Natal and spreads rapidly in humid conditions.',
      severity: 'Act soon — spreads quickly',
      severityColor: 'orange',
      treatment: [
        'Remove and destroy infected leaves — do not compost them',
        'Buy a fungicide containing mancozeb or tebuconazole',
        'Spray the whole plant including leaf undersides',
        'Repeat every 7 to 10 days',
        'Avoid overhead watering',
        'Plant rust-resistant bean varieties next season',
      ],
      homRemedy:
          'No fungicide available? Spray with baking soda solution — 1 tablespoon per litre of water with a few drops of dish soap every 3 days. Remove badly affected leaves by hand.',
    ),
    'blossom end rot': DiseaseInfo(
      name: 'blossom end rot',
      plainName: 'Blossom End Rot — Calcium Deficiency',
      description:
          'Dark sunken patches are appearing on the bottom end of your tomatoes, peppers, or squash. This is not a disease — it is caused by calcium deficiency in the fruit, usually due to irregular watering.',
      severity: 'Monitor — improve watering to prevent more',
      severityColor: 'orange',
      treatment: [
        'Water consistently — irregular watering is the main cause',
        'Mulch around the base of plants to retain soil moisture',
        'Buy calcium spray from your garden store and apply to leaves and developing fruits',
        'Avoid high nitrogen fertilisers — they compete with calcium uptake',
        'Remove affected fruits — they will not recover but new fruits will be healthy',
        'Check soil pH — calcium is unavailable in very acidic soil',
      ],
      homRemedy:
          'Dissolve 1 tablespoon of agricultural lime in 4 litres of water and water around the base of the plant. Crushed eggshells worked into the soil also add calcium over time.',
    ),
    'common scab': DiseaseInfo(
      name: 'common scab',
      plainName: 'Common Scab — Potato Skin Disease',
      description:
          'Rough corky patches or raised scabs are appearing on your potato skin. This is caused by a soil bacterium and is worse in dry alkaline soils. The potato is still edible but appearance is affected.',
      severity: 'Monitor — affects quality not survival',
      severityColor: 'orange',
      treatment: [
        'Potatoes are still safe to eat — just peel away the affected skin',
        'Water consistently during tuber formation — dry periods worsen scab',
        'Lower soil pH by adding sulphur or acidic compost — scab prefers alkaline soil',
        'Rotate crops — do not plant potatoes in the same spot for 3 years',
        'Plant scab-resistant varieties next season',
        'Avoid adding fresh manure or lime before planting potatoes',
      ],
      homRemedy:
          'No chemical treatment needed for mild scab. Focus on consistent watering and adding acidic compost like pine needles or peat to lower soil pH naturally.',
    ),
  };

  static DiseaseInfo getInfo(String label) {
    if (label.isEmpty) return _unknown();

    final lowerLabel = label.toLowerCase().trim();

    for (final key in diseases.keys) {
      if (key.toLowerCase() == lowerLabel) {
        return diseases[key]!;
      }
    }

    if (lowerLabel.contains('healthy')) return diseases['Healthy']!;
    if (lowerLabel.contains('early blight') ||
        lowerLabel.contains('alternaria solani')) {
      return diseases['Early_Blight']!;
    }
    if (lowerLabel.contains('late blight') ||
        lowerLabel.contains('phytophthora infestans')) {
      return diseases['Late_Blight']!;
    }
    if (lowerLabel.contains('leaf miner') ||
        lowerLabel.contains('leafminer')) {
      return diseases['Leaf_Miner']!;
    }
    if (lowerLabel.contains('nutrient') ||
        lowerLabel.contains('deficien') ||
        lowerLabel.contains('chlorosis')) {
      return diseases['nutrient deficiency']!;
    }
    if (lowerLabel.contains('powdery mildew') ||
        lowerLabel.contains('oidium')) {
      return diseases['powdery mildew']!;
    }
    if (lowerLabel.contains('rust') ||
        lowerLabel.contains('puccinia')) {
      return diseases['rust']!;
    }
    if (lowerLabel.contains('leaf spot') ||
        lowerLabel.contains('cercospora') ||
        lowerLabel.contains('septoria')) {
      return diseases['leaf spot']!;
    }
    if (lowerLabel.contains('mosaic') ||
        lowerLabel.contains('virus') ||
        lowerLabel.contains('viral')) {
      return diseases['mosaic virus']!;
    }
    if (lowerLabel.contains('pseudomonas') ||
        lowerLabel.contains('bacterial') ||
        lowerLabel.contains('bacteria') ||
        lowerLabel.contains('black rot') ||
        lowerLabel.contains('xanthomonas')) {
      return diseases['bacterial infection']!;
    }
    if (lowerLabel.contains('fungi') ||
        lowerLabel.contains('fungal') ||
        lowerLabel.contains('fungus')) {
      return diseases['fungal infection']!;
    }
    if (lowerLabel.contains('alternaria') ||
        lowerLabel.contains('blight')) {
      return diseases['alternaria']!;
    }
    if (lowerLabel.contains('aphid')) {
      return diseases['aphids']!;
    }
    if (lowerLabel.contains('whitefly') ||
        lowerLabel.contains('white fly')) {
      return diseases['whitefly']!;
    }
    if (lowerLabel.contains('root rot') ||
        lowerLabel.contains('pythium')) {
      return diseases['root rot']!;
    }
    if (lowerLabel.contains('sunburn') ||
        lowerLabel.contains('sun damage') ||
        lowerLabel.contains('sunscald')) {
      return diseases['sunburn']!;
    }
    if (lowerLabel.contains('spider mite') ||
        lowerLabel.contains('tetranychidae')) {
      return diseases['spider mites']!;
    }
    if (lowerLabel.contains('downy mildew') ||
        lowerLabel.contains('peronospora')) {
      return diseases['downy mildew']!;
    }
    if (lowerLabel.contains('botrytis') ||
        lowerLabel.contains('grey mould') ||
        lowerLabel.contains('gray mold')) {
      return diseases['botrytis']!;
    }
    if (lowerLabel.contains('grey leaf spot') ||
        lowerLabel.contains('gray leaf spot') ||
        lowerLabel.contains('cercospora zeae')) {
      return diseases['grey leaf spot']!;
    }
    if (lowerLabel.contains('maize streak') ||
        lowerLabel.contains('streak virus')) {
      return diseases['maize streak virus']!;
    }
    if (lowerLabel.contains('northern leaf blight') ||
        lowerLabel.contains('turcicum')) {
      return diseases['northern leaf blight']!;
    }
    if (lowerLabel.contains('fusarium') ||
        lowerLabel.contains('wilt')) {
      return diseases['fusarium wilt']!;
    }
    if (lowerLabel.contains('bean rust') ||
        lowerLabel.contains('uromyces')) {
      return diseases['bean rust']!;
    }
    if (lowerLabel.contains('blossom end rot') ||
        lowerLabel.contains('calcium deficien')) {
      return diseases['blossom end rot']!;
    }
    if (lowerLabel.contains('common scab') ||
        lowerLabel.contains('streptomyces')) {
      return diseases['common scab']!;
    }

    return _unknown();
  }

  static DiseaseInfo _unknown() {
    return const DiseaseInfo(
      name: 'Unknown',
      plainName: 'Could not identify the problem clearly',
      description:
          'We could not identify the disease clearly from this photo. Try taking another photo in better lighting, closer to the most affected leaf.',
      severity: 'Take another photo for better results',
      severityColor: 'grey',
      treatment: [
        'Take a clearer photo in good natural light',
        'Focus the camera directly on the most affected leaf',
        'Make sure the affected area fills most of the frame',
        'If the problem continues consult your local agricultural extension officer or agridealer',
      ],
      homRemedy:
          'Monitor your plant closely and try scanning again with a clearer photo.',
    );
  }
}