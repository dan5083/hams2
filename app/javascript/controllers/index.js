// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"

// Import nested PPI form controllers manually
import PpiFormTreatmentSelectionController from "./ppi_form/treatment_selection_controller"
import PpiFormOperationsFilterController from "./ppi_form/operations_filter_controller"
import PpiFormOperationSelectionController from "./ppi_form/operation_selection_controller"
import PpiFormEnpCalculatorController from "./ppi_form/enp_calculator_controller"

// Register nested controllers with explicit names
application.register("ppi-form--treatment-selection", PpiFormTreatmentSelectionController)
application.register("ppi-form--operations-filter", PpiFormOperationsFilterController)
application.register("ppi-form--operation-selection", PpiFormOperationSelectionController)
application.register("ppi-form--enp-calculator", PpiFormEnpCalculatorController)

// Auto-register other controllers (this will handle hello_controller.js etc.)
eagerLoadControllersFrom("controllers", application)
