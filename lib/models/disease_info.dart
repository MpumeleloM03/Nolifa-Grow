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
  };

  static DiseaseInfo getInfo(String label) {
    // Try exact match first
    if (diseases.containsKey(label)) {
      return diseases[label]!;
    }

    // Try partial match
    for (final key in diseases.keys) {
      if (label.toLowerCase().contains(key.toLowerCase()) ||
          key.toLowerCase().contains(label.toLowerCase())) {
        return diseases[key]!;
      }
    }

    // Default unknown
    return const DiseaseInfo(
      name: 'Unknown',
      plainName: 'Could not identify the problem',
      description:
          'We could not identify the disease clearly. Try taking another photo in better lighting, closer to the affected area.',
      severity: 'Take another photo',
      severityColor: 'grey',
      treatment: [
        'Take a clearer photo in good natural light',
        'Focus on the most affected leaf',
        'If the problem continues consult your local agricultural extension officer',
      ],
      homRemedy: 'Monitor your plant and try scanning again.',
    );
  }
}