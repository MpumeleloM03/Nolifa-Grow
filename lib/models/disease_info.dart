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
        lowerLabel.contains('phytophthora')) {
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
        lowerLabel.contains('bacteria')) {
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
        'If the problem continues consult your local agricultural extension officer',
      ],
      homRemedy:
          'Monitor your plant closely and try scanning again with a clearer photo.',
    );
  }
}