import 'package:ubuntu_core/ubuntu_core.dart';

extension OpenStore on MarketStore {
  /// Gets a farm through registration, verification, a plan and an inspection,
  /// so a test can list stock without repeating the steps.
  void openForSelling() {
    if (state.canSell && state.inspectionPassed) return;
    registerBusiness();
    for (final step in farmerSteps) {
      completeKyc(KycRole.farmer, step.id);
    }
    setPlan(Plan.starter);
    submitLandEvidence();
    requestInspection(InspectionRoute.surveyor);
    recordInspection(passed: true);
  }

  String? openAndList(Product p) {
    openForSelling();
    return list(p);
  }
}
