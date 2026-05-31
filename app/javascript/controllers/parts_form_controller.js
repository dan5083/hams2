// app/javascript/controllers/parts_form_controller.js
//
// Unlocked-mode treatment builder.
//
// This controller is attached to the part <form> in every mode, but it only
// does anything when the unlocked "Processing Instructions" section is on the
// page (i.e. when its treatment targets are present). In locked editing mode
// the form renders a different section that is driven by
// `locked_operations_controller.js`, so here we simply no-op.
import { Controller } from "@hotwired/stimulus"

// ---------------------------------------------------------------------------
// Static configuration (module-level so it isn't rebuilt on every connect)
// ---------------------------------------------------------------------------

const MAX_TREATMENTS = 5

const TREATMENT_NAMES = {
  stripping_only: "Strip Only",
  standard_anodising: "Standard Anodising",
  hard_anodising: "Hard Anodising",
  chromic_anodising: "Chromic Anodising",
  chemical_conversion: "Chemical Conversion",
  electroless_nickel_plating: "Electroless Nickel Plating"
}

// [borderColor, bgColor, badgeColor] applied when a treatment is selected.
const TREATMENT_BUTTON_COLORS = {
  standard_anodising: ["border-blue-500", "bg-blue-50", "bg-blue-500"],
  hard_anodising: ["border-purple-500", "bg-purple-50", "bg-purple-500"],
  chromic_anodising: ["border-green-500", "bg-green-50", "bg-green-500"],
  chemical_conversion: ["border-orange-500", "bg-orange-50", "bg-orange-500"],
  electroless_nickel_plating: ["border-indigo-500", "bg-indigo-50", "bg-indigo-500"],
  stripping_only: ["border-red-500", "bg-red-50", "bg-red-500"]
}

// All colour classes any button can hold, used when resetting appearance.
const TREATMENT_BUTTON_RESET_CLASSES = Object.values(TREATMENT_BUTTON_COLORS).flat()
const TREATMENT_BADGE_RESET_CLASSES = Object.values(TREATMENT_BUTTON_COLORS)
  .map(([, , badge]) => badge)
  .concat("text-white")

const ANODISING_TYPES = ["standard_anodising", "hard_anodising", "chromic_anodising"]

const JIG_TYPES = [
  "a secure titanium-to-part assy",
  "Wire (aluminium)",
  "Wire (steel)",
  "aluminium hooks",
  "steel hooks",
  "Expanding Jig",
  "Large Aluminum Expanding Jig",
  "Rotor Jig",
  "Vertical AllThread Jig",
  "Twisted Double Strap Jig",
  "Long Twisted Double Strap Jig",
  "Double Strap Jig",
  "3 Prong Jig",
  "4 Prong Jig",
  "Flat 3 Prong Jig",
  "Flat 4 Prong Jig",
  "M6 Jig (Metric)",
  "M6 Jig (UNC)",
  "Thin-stem M8 Jig",
  "Thick-stem M8 Jig",
  "Spring Jig",
  "Circular Spring Jig",
  "Aluminum Clamp Jig",
  "Wheel Nut Jig",
  "Muller Jigs",
  "Flat Piston Jig",
  "Upright Piston Jig",
  "Thick Wrap Around Jig",
  "Thin Wrap Around Jig",
  "Monobloc Jig",
  "Hytorque Jig"
]

const STRIPPING_TYPES = [
  { value: "anodising_stripping", label: "Anodising Stripping" },
  { value: "enp_stripping", label: "ENP Stripping" }
]

const STRIPPING_METHODS = {
  anodising_stripping: [
    { value: "chromic_phosphoric", label: "Chromic-Phosphoric Acid" },
    { value: "E28", label: "Oxidite E28" }
  ],
  enp_stripping: [
    { value: "nitric", label: "Nitric Acid" },
    { value: "metex_dekote", label: "Metex Dekote" }
  ]
}

const STRIPPING_PREVIEW_TEXT = {
  anodising_stripping: {
    chromic_phosphoric: "Strip anodising in chromic-phosphoric acid solution",
    E28: "Strip in Oxidite E28 - wait till fizzing starts and hold for 30 seconds"
  },
  enp_stripping: {
    nitric: "Strip ENP in nitric acid solution 30 to 40 minutes per 25 microns [or until black smut dissolves]",
    metex_dekote: "Strip ENP in Metex Dekote at 80 to 90°C, for approximately 20 microns per hour strip rate"
  }
}

const LOCAL_TREATMENTS = [
  { value: "none", label: "No Local Treatment" },
  { value: "LOCAL_ALOCHROM_1200_PEN", label: "Alochrom 1200 (Pen)" },
  { value: "LOCAL_SURTEC_650V_PEN", label: "SurTec 650V (Pen)" },
  { value: "LOCAL_PTFE_APPLICATION", label: "PTFE Application" }
]

// Criteria option lists. Some selects historically persisted their selection
// in the markup and some did not; that distinction is preserved by whether the
// render call passes the treatment's stored value (see generators below).
const ANODISING_ALLOYS = [
  { value: "", label: "Select alloy..." },
  { value: "6000_series", label: "6000 Series" },
  { value: "7075", label: "7075" },
  { value: "2014", label: "2014" },
  { value: "5083", label: "5083" },
  { value: "titanium", label: "Titanium" },
  { value: "general", label: "General" }
]

const ANODISING_THICKNESSES = [
  { value: "", label: "Select thickness..." },
  ...[5, 10, 15, 20, 25, 30, 40, 50, 60].map((t) => ({ value: String(t), label: `${t}μm` }))
]

const ANODIC_CLASSES = [
  { value: "", label: "Select class..." },
  { value: "class_1", label: "Class 1 (Undyed)" },
  { value: "class_2", label: "Class 2 (Dyed)" }
]

const CHROMIC_ALLOYS = [
  { value: "", label: "Select alloy..." },
  { value: "general", label: "General" },
  { value: "aluminium", label: "Aluminium" },
  { value: "6000_series", label: "6000 Series" },
  { value: "7075", label: "7075 (Standard Voltage Only)" },
  { value: "2024", label: "2024" }
]

const ENP_ALLOYS = [
  { value: "", label: "Select material..." },
  { value: "steel", label: "Steel" },
  { value: "stainless_steel", label: "Stainless Steel" },
  { value: "316_stainless_steel", label: "316 Stainless Steel" },
  { value: "aluminium", label: "Aluminium" },
  { value: "copper", label: "Copper" },
  { value: "brass", label: "Brass" },
  { value: "2000_series_alloys", label: "2000 Series Alloys" },
  { value: "stainless_steel_with_oxides", label: "Stainless Steel with Oxides" },
  { value: "copper_sans_electrical_contact", label: "Copper (Sans Electrical Contact)" },
  { value: "cope_rolled_aluminium", label: "Cope Rolled Aluminium" },
  { value: "mclaren_sta142_procedure_d", label: "McLaren STA142 Procedure D" }
]

const ENP_TYPES = [
  { value: "", label: "Select ENP type..." },
  { value: "high_phosphorous", label: "High Phosphorous" },
  { value: "medium_phosphorous", label: "Medium Phosphorous" },
  { value: "low_phosphorous", label: "Low Phosphorous" },
  { value: "ptfe_composite", label: "PTFE Composite" }
]

const MATERIAL_TYPES = [
  { value: "", label: "Select material type..." },
  { value: "aerospace_minimal", label: "Aerospace (Minimal Pretreatment)" },
  { value: "castings_plate", label: "Castings/Plate" },
  { value: "machined_wrought", label: "Machined/Wrought" },
  { value: "magnesium", label: "Magnesium" }
]

const SECONDARY_STRIPPING = [
  { value: "none", label: "No Stripping" },
  { value: "chromic_phosphoric", label: "Chromic-Phosphoric Acid" },
  { value: "E28", label: "Oxidite E28" },
  { value: "nitric", label: "Nitric Acid" },
  { value: "metex_dekote", label: "Metex Dekote" }
]

const DYE_COLORS = [
  { value: "none", label: "No Dye" },
  { value: "BLACK_DYE", label: "Black" },
  { value: "RED_DYE", label: "Red" },
  { value: "BLUE_DYE", label: "Blue" },
  { value: "GOLD_DYE", label: "Gold" },
  { value: "GREEN_DYE", label: "Green" }
]

const SEALING_METHODS = [
  { value: "none", label: "No Sealing" },
  { value: "SODIUM_DICHROMATE_SEAL", label: "Sodium Dichromate Seal" },
  { value: "OXIDITE_SECO_SEAL", label: "Oxidite SE-CO Seal" },
  { value: "HOT_WATER_DIP", label: "Hot Water Dip" },
  { value: "HOT_SEAL", label: "Hot Seal" },
  { value: "SURTEC_650V_SEAL", label: "SurTec 650V Seal" },
  { value: "DEIONISED_WATER_SEAL", label: "Deionised Water Seal" }
]

const MASKING_METHODS = [
  { method: "bungs", label: "Bungs", noun: "bungs" },
  { method: "pc21_polyester_tape", label: "PC21 - Polyester Tape", noun: "tape" },
  { method: "45_stopping_off_lacquer", label: "45 Stopping Off Lacquer", noun: "lacquer" }
]

// ---------------------------------------------------------------------------
// Small render helpers
// ---------------------------------------------------------------------------

// Render <option> tags. When `selected` is undefined no option is pre-selected,
// matching the legacy behaviour of selects that did not persist their value.
const optionsHtml = (items, selected) =>
  items
    .map(
      (item) =>
        `<option value="${item.value}"${
          selected !== undefined && item.value === selected ? " selected" : ""
        }>${item.label}</option>`
    )
    .join("")

export default class extends Controller {
  static targets = [
    "treatmentsField",
    "treatmentsContainer",
    "selectedContainer",
    "specificationField",
    "enpOptionsContainer",
    "enpPreHeatTreatmentSelect",
    "enpPreHeatTreatmentField",
    "enpHeatTreatmentSelect",
    "enpHeatTreatmentField",
    "enpStripTypeRadio",
    "enpStripTypeField",
    "enpStripMaskCheckbox",
    "enpStripMaskField",
    "aerospaceDefenseCheckbox",
    "aerospaceDefenseField",
    "treatmentSection",
    "formActions",
    "switchButton",
    "manualModeField"
  ]

  static values = {
    filterPath: String,
    detailsPath: String,
    previewPath: String,
    csrfToken: String
  }

  connect() {
    // Only the unlocked treatment-builder section uses this controller. If its
    // core targets are absent we're on a locked/copy/other view, so do nothing.
    if (
      !this.hasTreatmentsFieldTarget ||
      !this.hasTreatmentsContainerTarget ||
      !this.hasSelectedContainerTarget
    ) {
      return
    }

    this.treatments = []
    this.treatmentCounts = {
      standard_anodising: 0,
      hard_anodising: 0,
      chromic_anodising: 0,
      chemical_conversion: 0,
      electroless_nickel_plating: 0,
      stripping_only: 0
    }
    this.enpStripType = "nitric"
    this.enpStripMaskEnabled = false
    this.selectedEnpPreHeatTreatment = "none"
    this.selectedEnpHeatTreatment = "none"
    this.aerospaceDefense = false
    this.treatmentIdCounter = 0

    this.initializeExistingData()
    this.setupTreatmentButtons()
    this.setupEnpPreHeatTreatmentListener()
    this.setupEnpHeatTreatmentListener()
    this.setupEnpStripTypeListener()
    this.setupEnpStripMaskListener()
    this.setupAerospaceDefenseListener()
  }

  // ---------------------------------------------------------------------------
  // Networking
  // ---------------------------------------------------------------------------

  async postJson(url, body) {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfTokenValue
      },
      body: JSON.stringify(body)
    })

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`)
    }

    return response.json()
  }

  fetchOperations(criteria) {
    return this.postJson(this.filterPathValue, criteria)
  }

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  initializeExistingData() {
    try {
      this.treatments = JSON.parse(this.treatmentsFieldTarget.value || "[]")
      this.updateTreatmentCounts()
      this.renderTreatmentCards()

      if (this.hasEnpPreHeatTreatmentFieldTarget && this.hasEnpPreHeatTreatmentSelectTarget) {
        this.selectedEnpPreHeatTreatment = this.enpPreHeatTreatmentFieldTarget.value || "none"
        this.enpPreHeatTreatmentSelectTarget.value = this.selectedEnpPreHeatTreatment
      }

      if (this.hasEnpHeatTreatmentFieldTarget && this.hasEnpHeatTreatmentSelectTarget) {
        this.selectedEnpHeatTreatment = this.enpHeatTreatmentFieldTarget.value || "none"
        this.enpHeatTreatmentSelectTarget.value = this.selectedEnpHeatTreatment
      }

      if (this.hasAerospaceDefenseCheckboxTarget && this.hasAerospaceDefenseFieldTarget) {
        this.aerospaceDefense = this.aerospaceDefenseCheckboxTarget.checked
        this.aerospaceDefenseFieldTarget.value = this.aerospaceDefense
      }

      this.updateEnpOptionsVisibility()
      this.updatePreview()
    } catch (error) {
      console.error("Error parsing existing treatments:", error)
      this.treatments = []
    }
  }

  setupTreatmentButtons() {
    this.element
      .querySelectorAll(".treatment-btn")
      .forEach((button) => button.addEventListener("click", (e) => this.handleTreatmentClick(e)))
  }

  setupEnpPreHeatTreatmentListener() {
    if (!this.hasEnpPreHeatTreatmentSelectTarget || !this.hasEnpPreHeatTreatmentFieldTarget) return

    this.enpPreHeatTreatmentSelectTarget.addEventListener("change", (e) => {
      this.selectedEnpPreHeatTreatment = e.target.value
      this.enpPreHeatTreatmentFieldTarget.value = this.selectedEnpPreHeatTreatment
      this.updatePreview()
    })
  }

  setupEnpHeatTreatmentListener() {
    if (!this.hasEnpHeatTreatmentSelectTarget || !this.hasEnpHeatTreatmentFieldTarget) return

    this.enpHeatTreatmentSelectTarget.addEventListener("change", (e) => {
      this.selectedEnpHeatTreatment = e.target.value
      this.enpHeatTreatmentFieldTarget.value = this.selectedEnpHeatTreatment
      this.updatePreview()
    })
  }

  setupEnpStripTypeListener() {
    if (!this.hasEnpStripTypeRadioTarget || !this.hasEnpStripTypeFieldTarget) return

    this.enpStripTypeRadioTargets.forEach((radio) => {
      radio.addEventListener("change", (e) => {
        this.enpStripType = e.target.value
        this.enpStripTypeFieldTarget.value = this.enpStripType
        this.updatePreview()
      })
    })
  }

  setupEnpStripMaskListener() {
    if (!this.hasEnpStripMaskCheckboxTarget || !this.hasEnpStripMaskFieldTarget) return

    this.enpStripMaskCheckboxTarget.addEventListener("change", (e) => {
      this.enpStripMaskEnabled = e.target.checked
      this.updateEnpStripMaskField()
      this.updatePreview()
    })
  }

  setupAerospaceDefenseListener() {
    if (!this.hasAerospaceDefenseCheckboxTarget || !this.hasAerospaceDefenseFieldTarget) return

    this.aerospaceDefenseCheckboxTarget.addEventListener("change", (e) => {
      this.aerospaceDefense = e.target.checked
      this.aerospaceDefenseFieldTarget.value = this.aerospaceDefense
      this.updatePreview()
    })
  }

  // ---------------------------------------------------------------------------
  // Treatment add / remove
  // ---------------------------------------------------------------------------

  handleTreatmentClick(event) {
    event.preventDefault()
    const button = event.currentTarget
    const treatmentType = button.dataset.treatment

    if (this.treatments.length >= MAX_TREATMENTS) {
      alert(`Maximum ${MAX_TREATMENTS} treatments allowed`)
      return
    }

    this.addTreatment(treatmentType, button)
  }

  addTreatment(treatmentType, button) {
    this.treatmentIdCounter++

    const isStripOnly = treatmentType === "stripping_only"

    this.treatments.push({
      id: `treatment_${this.treatmentIdCounter}`,
      type: treatmentType,
      operation_id: null,
      selected_alloy: null,
      selected_material_type: null,
      target_thickness: null,
      selected_jig_type: null,
      stripping_type: isStripOnly ? "anodising_stripping" : null,
      stripping_method: isStripOnly ? "chromic_phosphoric" : null,
      masking_methods: {},
      stripping_enabled: false,
      stripping_type_secondary: "none",
      stripping_method_secondary: "none",
      sealing_method: "none",
      dye_color: "none",
      ptfe_enabled: false,
      local_treatment_type: "none"
    })

    this.treatmentCounts[treatmentType]++
    this.updateButtonAppearance(button, treatmentType)
    this.renderTreatmentCards()
    this.updateTreatmentsField()
    this.updateEnpOptionsVisibility()
  }

  removeTreatment(event) {
    const treatmentId = event.params.treatmentId
    const treatmentIndex = this.treatments.findIndex((t) => t.id === treatmentId)
    if (treatmentIndex === -1) return

    const treatment = this.treatments[treatmentIndex]
    this.treatmentCounts[treatment.type]--
    this.treatments.splice(treatmentIndex, 1)

    const button = this.element.querySelector(`[data-treatment="${treatment.type}"]`)
    if (this.treatmentCounts[treatment.type] === 0) {
      if (button) this.resetButtonAppearance(button)
    } else if (button) {
      const countBadge = button.querySelector(".count-badge")
      if (countBadge) countBadge.textContent = this.treatmentCounts[treatment.type]
    }

    this.renderTreatmentCards()
    this.updateTreatmentsField()
    this.updateEnpOptionsVisibility()
    this.updatePreview()
  }

  // ---------------------------------------------------------------------------
  // Button / count appearance
  // ---------------------------------------------------------------------------

  updateButtonAppearance(button, treatmentType) {
    const countBadge = button.querySelector(".count-badge")
    const [borderColor, bgColor, badgeColor] = TREATMENT_BUTTON_COLORS[treatmentType]

    button.classList.remove("border-gray-300")
    button.classList.add(borderColor, bgColor)
    countBadge.classList.remove("bg-gray-100")
    countBadge.classList.add(badgeColor, "text-white")
    countBadge.textContent = this.treatmentCounts[treatmentType]
  }

  resetButtonAppearance(button) {
    const countBadge = button.querySelector(".count-badge")

    button.classList.remove(...TREATMENT_BUTTON_RESET_CLASSES)
    button.classList.add("border-gray-300")

    if (countBadge) {
      countBadge.classList.remove(...TREATMENT_BADGE_RESET_CLASSES)
      countBadge.classList.add("bg-gray-100")
      countBadge.textContent = "0"
    }
  }

  updateTreatmentCounts() {
    Object.keys(this.treatmentCounts).forEach((type) => {
      this.treatmentCounts[type] = 0
    })

    this.treatments.forEach((treatment) => {
      if (Object.prototype.hasOwnProperty.call(this.treatmentCounts, treatment.type)) {
        this.treatmentCounts[treatment.type]++
      }
    })

    this.element.querySelectorAll(".treatment-btn").forEach((button) => {
      const treatmentType = button.dataset.treatment
      if (this.treatmentCounts[treatmentType] > 0) {
        this.updateButtonAppearance(button, treatmentType)
      }
    })
  }

  updateEnpOptionsVisibility() {
    if (!this.hasEnpOptionsContainerTarget) return

    const hasEnp = this.treatments.some((t) => t.type === "electroless_nickel_plating")
    this.enpOptionsContainerTarget.style.display = hasEnp ? "block" : "none"
  }

  // ---------------------------------------------------------------------------
  // Treatment card rendering
  // ---------------------------------------------------------------------------

  renderTreatmentCards() {
    if (!this.hasTreatmentsContainerTarget) return

    if (this.treatments.length === 0) {
      this.treatmentsContainerTarget.innerHTML =
        '<p class="text-gray-500 text-sm">Select treatments above to configure them</p>'
      return
    }

    this.treatmentsContainerTarget.innerHTML = this.treatments
      .map((treatment, index) => this.generateTreatmentCardHTML(treatment, index))
      .join("")

    this.addTreatmentCardListeners()
  }

  generateTreatmentCardHTML(treatment, index) {
    const treatmentName = this.formatTreatmentName(treatment.type)
    const isStripOnly = treatment.type === "stripping_only"
    const isENP = treatment.type === "electroless_nickel_plating"
    const isChemicalConversion = treatment.type === "chemical_conversion"
    const isAnodising = ANODISING_TYPES.includes(treatment.type)

    return `
      <div class="border border-gray-200 rounded-lg p-4 bg-gray-50" data-treatment-id="${treatment.id}">
        <div class="flex justify-between items-center mb-4">
          <h4 class="font-medium text-gray-900">${treatmentName} Treatment ${index + 1}</h4>
          <button type="button" class="text-red-600 hover:text-red-800 text-xl font-bold" data-action="click->parts-form#removeTreatment" data-parts-form-treatment-id-param="${treatment.id}">×</button>
        </div>

        ${
          isAnodising && this.aerospaceDefense
            ? `
        <div class="mb-3 p-2 bg-yellow-50 border border-yellow-200 rounded text-xs text-yellow-800">
          <strong>Aerospace/Defense:</strong> Foil verification will be included for this anodising treatment
        </div>
        `
            : ""
        }

        <!-- Jig Selection (Per-treatment) -->
        <div class="mb-4">
          <label class="block text-sm font-medium text-gray-700 mb-2">Jig Type</label>
          <select class="jig-type-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" data-treatment-id="${treatment.id}" required>
            <option value="">Select jig type...</option>
            ${JIG_TYPES.map(
              (jig) =>
                `<option value="${jig}" ${
                  treatment.selected_jig_type === jig ? "selected" : ""
                }>${jig}</option>`
            ).join("")}
          </select>
          <p class="mt-1 text-xs text-gray-500">Required for jigging operations in this treatment</p>
        </div>

        ${isStripOnly ? this.generateStripOnlySelectionHTML(treatment) : this.generateOperationSelectionHTML(treatment)}

        ${isStripOnly ? "" : this.generateCriteriaHTML(treatment)}

        ${isENP || isStripOnly || isChemicalConversion ? "" : this.generateTreatmentModifiersHTML(treatment)}

        ${isStripOnly ? this.generateStripOnlyModifiersHTML(treatment) : ""}
      </div>
    `
  }

  generateOperationSelectionHTML() {
    return `
      <div class="mb-4">
        <label class="block text-sm font-medium text-gray-700 mb-2">Select Operation</label>
        <div class="operations-list space-y-2 max-h-40 overflow-y-auto border border-gray-200 rounded p-3 bg-white">
          <p class="text-gray-500 text-xs">Configure criteria below to see operations</p>
        </div>
      </div>
    `
  }

  generateStripOnlySelectionHTML(treatment) {
    return `
      <div class="mb-4">
        <h5 class="text-sm font-medium text-gray-700 mb-3">Strip Configuration</h5>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 mb-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Strip Type</label>
            <select class="strip-type-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-red-500 focus:border-red-500 sm:text-sm" data-treatment-id="${treatment.id}">
              ${optionsHtml(STRIPPING_TYPES, treatment.stripping_type)}
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Strip Method</label>
            <select class="strip-method-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-red-500 focus:border-red-500 sm:text-sm" data-treatment-id="${treatment.id}">
              ${optionsHtml(this.getStrippingMethodsForType(treatment.stripping_type), treatment.stripping_method)}
            </select>
          </div>
        </div>

        <div class="strip-operation-preview bg-white border border-gray-200 rounded p-3 mt-4">
          <h6 class="text-sm font-medium text-gray-700 mb-2">Strip Operation Preview:</h6>
          <p class="text-sm text-gray-600" data-strip-preview="${treatment.id}">
            ${this.getStrippingPreviewText(treatment.stripping_type, treatment.stripping_method)}
          </p>
        </div>
      </div>
    `
  }

  // Masking method rows, shared between strip-only and anodising modifiers.
  // `optional` switches the placeholder wording and adds the explanatory note.
  generateMaskingMethodsHTML(treatment, { optional }) {
    const rows = MASKING_METHODS.map(({ method, label, noun }) => {
      const value = treatment.masking_methods?.[method]
      const checked = value !== undefined
      const suffix = optional ? " (optional)" : ""
      return `
              <div class="flex items-center space-x-3">
                <label class="flex items-center">
                  <input type="checkbox" class="masking-checkbox rounded border-gray-300 text-teal-600" data-treatment-id="${treatment.id}" data-method="${method}" ${checked ? "checked" : ""}>
                  <span class="ml-2 text-sm text-gray-700">${label}</span>
                </label>
                <input type="text" class="masking-location flex-1 border border-gray-300 rounded-md px-2 py-1 text-sm" data-treatment-id="${treatment.id}" data-method="${method}" placeholder="Location/notes for ${noun}${suffix}..." value="${value || ""}" ${checked ? "" : 'style="display: none;"'}>
              </div>`
    }).join("")

    return `
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">Masking Methods</label>
            <div class="space-y-2">${rows}
            </div>${
              optional
                ? '\n            <p class="mt-2 text-xs text-gray-500">Masking protects areas that should not be stripped. Location details are optional.</p>'
                : ""
            }
          </div>`
  }

  generateStripOnlyModifiersHTML(treatment) {
    return `
      <div class="border-t border-gray-200 pt-4 mt-4">
        <h5 class="text-sm font-medium text-gray-700 mb-3">Strip Modifiers</h5>

        <div class="space-y-4">
          ${this.generateMaskingMethodsHTML(treatment, { optional: true })}
        </div>
      </div>
    `
  }

  // ---------------------------------------------------------------------------
  // Criteria selection
  // ---------------------------------------------------------------------------

  generateCriteriaHTML(treatment) {
    switch (treatment.type) {
      case "chemical_conversion":
        return this.generateChemicalConversionCriteriaHTML(treatment)
      case "electroless_nickel_plating":
        return this.generateENPCriteriaHTML(treatment)
      case "chromic_anodising":
        return this.generateChromicCriteriaHTML(treatment)
      default:
        return this.generateAnodisingCriteriaHTML(treatment)
    }
  }

  generateChemicalConversionCriteriaHTML(treatment) {
    return `
      <div class="grid grid-cols-1 gap-4 mb-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Material Type</label>
          <select class="material-type-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-orange-500 focus:border-orange-500 sm:text-sm" data-treatment-id="${treatment.id}">
            ${optionsHtml(MATERIAL_TYPES, treatment.selected_material_type)}
          </select>
          <p class="mt-1 text-xs text-gray-500">Material type determines required pretreatment sequence</p>
        </div>
      </div>
    `
  }

  generateChromicCriteriaHTML(treatment) {
    return `
      <div class="grid grid-cols-1 gap-4 mb-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Alloy</label>
          <select class="alloy-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-green-500 focus:border-green-500 sm:text-sm" data-treatment-id="${treatment.id}">
            ${optionsHtml(CHROMIC_ALLOYS, treatment.selected_alloy)}
          </select>
          <p class="mt-1 text-xs text-gray-500">Chromic anodising - no class selection needed</p>
        </div>
      </div>
    `
  }

  generateENPCriteriaHTML(treatment) {
    return `
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-3 mb-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Alloy/Material</label>
          <select class="alloy-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm" data-treatment-id="${treatment.id}">
            ${optionsHtml(ENP_ALLOYS, treatment.selected_alloy)}
          </select>
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">ENP Type</label>
          <select class="enp-type-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm" data-treatment-id="${treatment.id}">
            ${optionsHtml(ENP_TYPES)}
          </select>
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Target Thickness (μm)</label>
          <input type="number" class="thickness-input mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm" data-treatment-id="${treatment.id}" placeholder="e.g., 25" min="1" max="100" value="${treatment.target_thickness || ""}">
        </div>
      </div>
    `
  }

  generateAnodisingCriteriaHTML(treatment) {
    return `
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-3 mb-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Alloy</label>
          <select class="alloy-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" data-treatment-id="${treatment.id}">
            ${optionsHtml(ANODISING_ALLOYS)}
          </select>
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Target Thickness (μm)</label>
          <select class="thickness-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" data-treatment-id="${treatment.id}">
            ${optionsHtml(ANODISING_THICKNESSES)}
          </select>
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Anodic Class</label>
          <select class="anodic-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" data-treatment-id="${treatment.id}">
            ${optionsHtml(ANODIC_CLASSES)}
          </select>
        </div>
      </div>
    `
  }

  // ---------------------------------------------------------------------------
  // Treatment modifiers (anodising)
  // ---------------------------------------------------------------------------

  generateTreatmentModifiersHTML(treatment) {
    const show = ANODISING_TYPES.includes(treatment.type)
    const gridCols = show ? "sm:grid-cols-3" : "sm:grid-cols-1"

    return `
      <div class="border-t border-gray-200 pt-4 mt-4">
        <h5 class="text-sm font-medium text-gray-700 mb-3">Treatment Modifiers</h5>

        <div class="space-y-4">
          ${this.generateMaskingMethodsHTML(treatment, { optional: false })}

          <div class="grid grid-cols-1 gap-4 ${gridCols}">
            <!-- Stripping Method -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Stripping</label>
              <select class="stripping-method-select w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-red-500 focus:border-red-500 sm:text-sm" data-treatment-id="${treatment.id}">
                ${optionsHtml(SECONDARY_STRIPPING, treatment.stripping_method_secondary)}
              </select>
            </div>

            ${
              show
                ? `
            <!-- Dye Selection (for anodising only) -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Dye Color</label>
              <select class="dye-color-select w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-purple-500 focus:border-purple-500 sm:text-sm" data-treatment-id="${treatment.id}">
                ${optionsHtml(DYE_COLORS, treatment.dye_color)}
              </select>
            </div>
            `
                : ""
            }

            ${
              show
                ? `
            <!-- Sealing Method (for anodising only) -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Sealing</label>
              <select class="sealing-method-select w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-purple-500 focus:border-purple-500 sm:text-sm" data-treatment-id="${treatment.id}">
                ${optionsHtml(SEALING_METHODS, treatment.sealing_method)}
              </select>
            </div>
            `
                : ""
            }
          </div>

          ${
            show
              ? `
          <!-- PTFE Toggle (for anodising only) -->
          <div class="pt-2 border-t border-gray-200">
            <label class="flex items-center">
              <input type="checkbox" class="ptfe-checkbox rounded border-gray-300 text-blue-600 shadow-sm focus:border-blue-300 focus:ring focus:ring-offset-0 focus:ring-blue-200 focus:ring-opacity-50" data-treatment-id="${treatment.id}" ${treatment.ptfe_enabled ? "checked" : ""}>
              <span class="ml-2 text-sm font-medium text-gray-700">Apply PTFE Treatment</span>
            </label>
            <p class="mt-1 text-xs text-gray-500">Anolube treatment applied after sealing</p>
          </div>
          `
              : ""
          }

          ${
            show
              ? `
          <!-- Local Treatment Selection (for anodising only) -->
          <div class="pt-2 border-t border-gray-200">
            <label class="block text-sm font-medium text-gray-700 mb-2">Local Treatment</label>
            <select class="local-treatment-select w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-teal-500 focus:border-teal-500 sm:text-sm" data-treatment-id="${treatment.id}">
              ${optionsHtml(LOCAL_TREATMENTS, treatment.local_treatment_type)}
            </select>
            <p class="mt-1 text-xs text-gray-500">Applied after masking removal operations</p>
          </div>
          `
              : ""
          }
        </div>
      </div>
    `
  }

  // ---------------------------------------------------------------------------
  // Strip helpers
  // ---------------------------------------------------------------------------

  getStrippingMethodsForType(strippingType) {
    return STRIPPING_METHODS[strippingType] || []
  }

  getStrippingPreviewText(strippingType, strippingMethod) {
    if (!strippingType || !strippingMethod) return "Select strip type and method to see preview"
    return STRIPPING_PREVIEW_TEXT[strippingType]?.[strippingMethod] || "Strip as specified"
  }

  updateStripMethodDropdown(treatmentId, stripType) {
    const card = this.treatmentsContainerTarget.querySelector(`[data-treatment-id="${treatmentId}"]`)
    const methodSelect = card?.querySelector(".strip-method-select")
    if (!methodSelect) return

    const methods = this.getStrippingMethodsForType(stripType)
    methodSelect.innerHTML = optionsHtml(methods)

    const treatment = this.treatments.find((t) => t.id === treatmentId)
    if (treatment && methods.length > 0) {
      treatment.stripping_method = methods[0].value
      methodSelect.value = methods[0].value
    }
  }

  updateStripPreview(treatmentId, stripType, stripMethod) {
    const previewElement = this.treatmentsContainerTarget.querySelector(
      `[data-strip-preview="${treatmentId}"]`
    )
    if (previewElement) {
      previewElement.textContent = this.getStrippingPreviewText(stripType, stripMethod)
    }
  }

  // ---------------------------------------------------------------------------
  // Card listeners & change handling
  // ---------------------------------------------------------------------------

  addTreatmentCardListeners() {
    if (!this.hasTreatmentsContainerTarget) return

    this.treatmentsContainerTarget.querySelectorAll("select, input").forEach((element) => {
      element.addEventListener("change", (e) => this.handleTreatmentChange(e))
      if (element.type === "text") {
        element.addEventListener("input", (e) => this.handleTreatmentChange(e))
      }
    })

    this.treatments.forEach((treatment) => {
      if (treatment.type !== "stripping_only") {
        this.loadOperationsForTreatment(treatment.id)
      }
    })
  }

  handleTreatmentChange(event) {
    const treatmentId = event.target.dataset.treatmentId
    if (!treatmentId) return

    const treatment = this.treatments.find((t) => t.id === treatmentId)
    if (!treatment) return

    const target = event.target
    const has = (className) => target.classList.contains(className)

    if (has("jig-type-select")) {
      treatment.selected_jig_type = target.value
    }

    if (has("material-type-select")) {
      treatment.selected_material_type = target.value
      this.loadOperationsForTreatment(treatmentId)
    }

    if (has("strip-type-select")) {
      treatment.stripping_type = target.value
      this.updateStripMethodDropdown(treatmentId, treatment.stripping_type)
      this.updateStripPreview(treatmentId, treatment.stripping_type, treatment.stripping_method)
    }

    if (has("strip-method-select")) {
      treatment.stripping_method = target.value
      this.updateStripPreview(treatmentId, treatment.stripping_type, treatment.stripping_method)
    }

    if (has("alloy-select") && treatment.type === "electroless_nickel_plating") {
      treatment.selected_alloy = target.value
    }

    if (has("alloy-select") && treatment.type === "chromic_anodising") {
      treatment.selected_alloy = target.value
    }

    if (has("thickness-input") && treatment.type === "electroless_nickel_plating") {
      treatment.target_thickness = parseFloat(target.value) || null
    }

    if (has("masking-checkbox")) {
      const method = target.dataset.method
      const locationInput = this.treatmentsContainerTarget.querySelector(
        `input[data-treatment-id="${treatmentId}"][data-method="${method}"].masking-location`
      )

      if (target.checked) {
        treatment.masking_methods[method] = ""
        if (locationInput) {
          locationInput.style.display = ""
          locationInput.focus()
        }
      } else {
        delete treatment.masking_methods[method]
        if (locationInput) {
          locationInput.style.display = "none"
          locationInput.value = ""
        }
      }
    }

    if (has("masking-location")) {
      treatment.masking_methods[target.dataset.method] = target.value
    }

    if (has("stripping-method-select")) {
      treatment.stripping_method_secondary = target.value
      treatment.stripping_enabled = target.value !== "none"
    }

    if (has("sealing-method-select")) {
      treatment.sealing_method = target.value
    }

    if (has("dye-color-select")) {
      treatment.dye_color = target.value
    }

    if (has("ptfe-checkbox")) {
      treatment.ptfe_enabled = target.checked
    }

    if (has("local-treatment-select")) {
      treatment.local_treatment_type = target.value
    }

    if (
      has("alloy-select") ||
      has("material-type-select") ||
      has("thickness-select") ||
      has("thickness-input") ||
      has("anodic-select") ||
      has("enp-type-select")
    ) {
      this.loadOperationsForTreatment(treatmentId)
    }

    this.updateTreatmentsField()
    this.updatePreview()
  }

  // ---------------------------------------------------------------------------
  // Operation loading & selection
  // ---------------------------------------------------------------------------

  async loadOperationsForTreatment(treatmentId) {
    if (!this.hasTreatmentsContainerTarget) return

    const treatment = this.treatments.find((t) => t.id === treatmentId)
    if (!treatment || treatment.type === "stripping_only") return

    const card = this.treatmentsContainerTarget.querySelector(`[data-treatment-id="${treatmentId}"]`)
    const operationsList = card?.querySelector(".operations-list")
    if (!operationsList) return

    try {
      const criteria = this.buildCriteriaForTreatment(treatment, card)
      const operations = await this.fetchOperations(criteria)
      this.displayOperationsInCard(operations, operationsList, treatmentId)
    } catch (error) {
      console.error("Error loading operations:", error)
      operationsList.innerHTML = '<p class="text-red-500 text-xs">Error loading operations</p>'
    }
  }

  buildCriteriaForTreatment(treatment, card) {
    const criteria = { anodising_types: [treatment.type] }

    if (treatment.type === "electroless_nickel_plating") {
      const alloy = card.querySelector(".alloy-select")?.value
      const enpType = card.querySelector(".enp-type-select")?.value
      const thicknessValue = card.querySelector(".thickness-input")?.value

      if (alloy) criteria.alloys = [alloy]
      if (enpType) criteria.enp_types = [enpType]
      if (thicknessValue) {
        const thickness = parseFloat(thicknessValue)
        criteria.target_thicknesses = [thickness]
        treatment.target_thickness = thickness
      }
    } else if (treatment.type === "chromic_anodising") {
      const alloy = card.querySelector(".alloy-select")?.value
      if (alloy) criteria.alloys = [alloy]
    } else if (treatment.type !== "chemical_conversion") {
      const alloy = card.querySelector(".alloy-select")?.value
      const thickness = card.querySelector(".thickness-select")?.value
      const anodic = card.querySelector(".anodic-select")?.value

      if (alloy) criteria.alloys = [alloy]
      if (thickness) criteria.target_thicknesses = [parseFloat(thickness)]
      if (anodic) criteria.anodic_classes = [anodic]
    }

    return criteria
  }

  displayOperationsInCard(operations, container, treatmentId) {
    if (operations.length === 0) {
      container.innerHTML = '<p class="text-gray-500 text-xs">No matching operations found</p>'
      return
    }

    container.innerHTML = operations
      .map(
        (op) => `
      <div class="bg-white border border-gray-200 rounded px-2 py-1 cursor-pointer hover:bg-blue-50 text-xs operation-card"
           data-operation-id="${op.id}"
           data-treatment-id="${treatmentId}">
        <div class="flex justify-between items-center">
          <span class="font-medium">${op.display_name || op.id.replace(/_/g, " ")}</span>
          <span class="select-operation-indicator text-blue-600 text-xs font-medium">Select</span>
        </div>
        <p class="text-gray-600 mt-1">${op.operation_text}</p>
        ${op.specifications ? `<p class="text-purple-600 text-xs mt-1">${op.specifications}</p>` : ""}
      </div>
    `
      )
      .join("")

    container.querySelectorAll(".operation-card").forEach((card) => {
      card.addEventListener("click", () =>
        this.selectOperationForTreatment(card.dataset.operationId, card.dataset.treatmentId)
      )
    })
  }

  selectOperationForTreatment(operationId, treatmentId) {
    const treatment = this.treatments.find((t) => t.id === treatmentId)
    if (!treatment) {
      console.error(`Treatment not found: ${treatmentId}`)
      return
    }

    treatment.operation_id = operationId

    const card = this.treatmentsContainerTarget.querySelector(`[data-treatment-id="${treatmentId}"]`)

    // Backfill criteria values that drive downstream film-reading requirements.
    if (treatment.type === "electroless_nickel_plating") {
      const alloy = card?.querySelector(".alloy-select")
      const thickness = card?.querySelector(".thickness-input")
      if (alloy?.value && !treatment.selected_alloy) treatment.selected_alloy = alloy.value
      if (thickness?.value) treatment.target_thickness = parseFloat(thickness.value)
    }

    if (treatment.type === "chromic_anodising") {
      const alloy = card?.querySelector(".alloy-select")
      if (alloy?.value && !treatment.selected_alloy) treatment.selected_alloy = alloy.value
    }

    if (treatment.type === "chemical_conversion") {
      const materialType = card?.querySelector(".material-type-select")
      if (materialType?.value && !treatment.selected_material_type) {
        treatment.selected_material_type = materialType.value
      }
    }

    this.highlightSelectedOperation(card, operationId)

    this.updateTreatmentsField()
    this.updatePreview()
  }

  highlightSelectedOperation(card, operationId) {
    const operationsList = card?.querySelector(".operations-list")
    if (!operationsList) return

    operationsList.querySelectorAll(".operation-card").forEach((div) => {
      div.classList.remove("bg-blue-100", "border-blue-400")
      div.classList.add("bg-white", "border-gray-200")
      const indicator = div.querySelector(".select-operation-indicator")
      if (indicator) {
        indicator.textContent = "Select"
        indicator.classList.remove("text-green-600", "font-bold")
        indicator.classList.add("text-blue-600")
      }
    })

    const selectedDiv = operationsList.querySelector(`[data-operation-id="${operationId}"]`)
    if (selectedDiv) {
      selectedDiv.classList.remove("bg-white", "border-gray-200")
      selectedDiv.classList.add("bg-blue-100", "border-blue-400")
      const indicator = selectedDiv.querySelector(".select-operation-indicator")
      if (indicator) {
        indicator.textContent = "✓ Selected"
        indicator.classList.remove("text-blue-600")
        indicator.classList.add("text-green-600", "font-bold")
      }
    }
  }

  // ---------------------------------------------------------------------------
  // ENP strip/mask & field persistence
  // ---------------------------------------------------------------------------

  updateEnpStripMaskField() {
    if (!this.hasEnpStripMaskFieldTarget) return

    const ops = this.enpStripMaskEnabled ? this.getEnpStripMaskOperationIds(this.enpStripType) : []
    this.enpStripMaskFieldTarget.value = JSON.stringify(ops)
  }

  getEnpStripMaskOperationIds(stripType) {
    const stripOperation = stripType === "metex_dekote" ? "ENP_STRIP_METEX" : "ENP_STRIP_NITRIC"
    return ["ENP_MASK", "ENP_MASKING_CHECK", stripOperation, "ENP_STRIP_MASKING", "ENP_MASKING_CHECK_FINAL"]
  }

  updateTreatmentsField() {
    if (!this.hasTreatmentsFieldTarget) return
    this.treatmentsFieldTarget.value = JSON.stringify(this.treatments)
  }

  formatTreatmentName(treatmentType) {
    return (
      TREATMENT_NAMES[treatmentType] ||
      treatmentType
        .replace("_anodising", "")
        .replace("_conversion", "")
        .replace("_nickel_plating", "")
        .split("_")
        .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
        .join(" ")
    )
  }

  // ---------------------------------------------------------------------------
  // Live preview
  // ---------------------------------------------------------------------------

  async updatePreview() {
    if (!this.hasSelectedContainerTarget) return

    const clearSpecification = () => {
      if (this.hasSpecificationFieldTarget) this.specificationFieldTarget.value = ""
    }

    if (this.treatments.length === 0) {
      this.selectedContainerTarget.innerHTML =
        '<p class="text-gray-500 text-sm">No treatments selected</p>'
      clearSpecification()
      return
    }

    const treatmentsWithOperations = this.treatments.filter(
      (t) => t.operation_id || t.type === "stripping_only"
    )

    if (treatmentsWithOperations.length === 0) {
      this.selectedContainerTarget.innerHTML =
        '<p class="text-gray-500 text-sm">Select operations for treatments to see preview</p>'
      clearSpecification()
      return
    }

    if (treatmentsWithOperations.some((t) => !t.selected_jig_type)) {
      this.selectedContainerTarget.innerHTML =
        '<p class="text-yellow-600 text-sm">Select jig types for all treatments to see preview</p>'
      clearSpecification()
      return
    }

    try {
      const requestData = {
        treatments_data: treatmentsWithOperations.map((t) => this.serializeTreatment(t)),
        aerospace_defense: this.aerospaceDefense,
        selected_enp_pre_heat_treatment: this.selectedEnpPreHeatTreatment,
        selected_enp_heat_treatment: this.selectedEnpHeatTreatment
      }

      if (this.enpStripMaskEnabled) {
        requestData.enp_strip_type = this.enpStripType
        requestData.selected_operations = this.getEnpStripMaskOperationIds(this.enpStripType)
      }

      const data = await this.postJson(this.previewPathValue, requestData)
      const operations = data.operations || []

      if (operations.length === 0) {
        this.selectedContainerTarget.innerHTML =
          '<p class="text-yellow-600 text-sm">No operations generated - check treatment configuration</p>'
        clearSpecification()
        return
      }

      this.selectedContainerTarget.innerHTML = operations
        .map((op, index) => this.renderPreviewOperation(op, index))
        .join("")
    } catch (error) {
      console.error("Error updating preview:", error)
      this.selectedContainerTarget.innerHTML =
        '<p class="text-red-500 text-sm">Error loading preview</p>'
    }
  }

  // Convert the internal treatment shape into the payload the server expects.
  serializeTreatment(treatment) {
    const secondary = treatment.stripping_method_secondary
    const hasSecondaryStrip = secondary !== "none"
    const isEnpStrip = secondary === "nitric" || secondary === "metex_dekote"

    return {
      id: treatment.id,
      type: treatment.type,
      operation_id: treatment.operation_id,
      selected_alloy: treatment.selected_alloy,
      selected_material_type: treatment.selected_material_type,
      target_thickness: treatment.target_thickness,
      selected_jig_type: treatment.selected_jig_type,
      stripping_type: treatment.stripping_type,
      stripping_method: treatment.stripping_method,
      masking: {
        enabled: Object.keys(treatment.masking_methods || {}).length > 0,
        methods: treatment.masking_methods || {}
      },
      stripping: {
        enabled: hasSecondaryStrip,
        type: hasSecondaryStrip ? (isEnpStrip ? "enp_stripping" : "anodising_stripping") : null,
        method: hasSecondaryStrip ? secondary : null
      },
      sealing: {
        enabled: treatment.sealing_method !== "none",
        type: treatment.sealing_method !== "none" ? treatment.sealing_method : null
      },
      dye: {
        enabled: treatment.dye_color !== "none",
        color: treatment.dye_color !== "none" ? treatment.dye_color : null
      },
      ptfe: { enabled: treatment.ptfe_enabled },
      local_treatment: {
        enabled: treatment.local_treatment_type !== "none",
        type: treatment.local_treatment_type !== "none" ? treatment.local_treatment_type : null
      }
    }
  }

  renderPreviewOperation(op, index) {
    const { bgColor, textColor, autoLabel } = this.previewOperationStyle(op)
    const text = op.id === "OCV_CHECK" ? op.operation_text.replace(/\n/g, "<br>") : op.operation_text

    return `
          <div class="${bgColor} rounded px-3 py-2">
            <span class="text-sm ${textColor}">
              <strong>${index + 1}.</strong>
              ${op.display_name}: ${text}
              ${autoLabel}
            </span>
          </div>
        `
  }

  // Determine the colour scheme and badge for a previewed operation. Order
  // matters: later matches override earlier ones (mirrors the original cascade).
  previewOperationStyle(op) {
    const id = op.id || ""
    const displayName = op.display_name || ""

    let style = { bgColor: "bg-blue-100 border border-blue-300", textColor: "text-gray-900", autoLabel: "" }

    if (op.auto_inserted) {
      style = {
        bgColor: "bg-gray-100 border border-gray-300",
        textColor: "italic text-gray-600",
        autoLabel: '<span class="text-xs text-gray-500 ml-2">(auto-inserted)</span>'
      }
    }

    if (id === "WATER_BREAK_TEST") {
      style = {
        bgColor: "bg-red-50 border border-red-200",
        textColor: "text-red-800",
        autoLabel: '<span class="text-xs text-red-600 ml-2">(requires manual recording)</span>'
      }
    }

    if (id === "FOIL_VERIFICATION" || id.startsWith("FOIL_VERIFICATION_")) {
      style = {
        bgColor: "bg-yellow-50 border border-yellow-200",
        textColor: "text-yellow-800",
        autoLabel: '<span class="text-xs text-yellow-600 ml-2">(per-treatment verification)</span>'
      }
    }

    if (id === "OCV_CHECK") {
      style = {
        bgColor: "bg-cyan-50 border border-cyan-200",
        textColor: "text-cyan-800",
        autoLabel: '<span class="text-xs text-cyan-600 ml-2">(aerospace/defense monitoring)</span>'
      }
    }

    if (id.includes("_DYE") || displayName.includes("Dye")) {
      style = {
        bgColor: "bg-purple-50 border border-purple-200",
        textColor: "text-purple-800",
        autoLabel: '<span class="text-xs text-purple-600 ml-2">(dye operation)</span>'
      }
    }

    if (id.startsWith("PRE_ENP_HEAT_TREAT")) {
      style = {
        bgColor: "bg-amber-50 border border-amber-200",
        textColor: "text-amber-800",
        autoLabel: '<span class="text-xs text-amber-600 ml-2">(ENP pre-heat treatment)</span>'
      }
    }

    if (id.startsWith("POST_ENP_HEAT_TREAT") || id.includes("ENP_POST_HEAT_TREAT") || id.includes("ENP_BAKE")) {
      style = {
        bgColor: "bg-orange-50 border border-orange-200",
        textColor: "text-orange-800",
        autoLabel: '<span class="text-xs text-orange-600 ml-2">(ENP post-heat treatment)</span>'
      }
    }

    if (id.startsWith("LOCAL_")) {
      style = {
        bgColor: "bg-teal-50 border border-teal-200",
        textColor: "text-teal-800",
        autoLabel: '<span class="text-xs text-teal-600 ml-2">(local treatment)</span>'
      }
    }

    if (id === "STRIPPING" || displayName.includes("Strip")) {
      style = {
        bgColor: "bg-red-100 border border-red-300",
        textColor: "text-red-900",
        autoLabel: '<span class="text-xs text-red-600 ml-2">(strip-only treatment)</span>'
      }
    }

    return style
  }

  // ---------------------------------------------------------------------------
  // Switch to manual mode (was the inline `switchToManualMode` global)
  // ---------------------------------------------------------------------------

  switchToManual() {
    if (this.treatments.length === 0) {
      alert("Please configure some treatments first before switching to manual mode.")
      return
    }

    const hasOperations = this.treatments.some((t) => t.operation_id || t.type === "stripping_only")
    if (!hasOperations) {
      alert("Please select operations for your treatments before switching to manual mode.")
      return
    }

    if (
      confirm(
        "Switch to manual editing mode? This will save your current configuration and allow you to customize each operation individually. You cannot return to automatic mode after this change."
      )
    ) {
      if (this.hasManualModeFieldTarget) this.manualModeFieldTarget.value = "true"
      this.element.submit()
    }
  }

  // ---------------------------------------------------------------------------
  // Copy from existing part (was the inline `copyPartOperations` /
  // `switchToManualModeWithOperations` globals). Triggered by the copy search's
  // `autocomplete:select` event.
  // ---------------------------------------------------------------------------

  async copyFromPart(event) {
    const part = event.detail.item
    const input = event.detail.input

    if (input) {
      input.value = `Copying from: ${part.part_number} (${part.customer_name})`
      input.disabled = true
      input.style.backgroundColor = "#f9fafb"
    }

    try {
      const response = await fetch(`/parts/${part.id}/copy_operations`, {
        method: "GET",
        headers: { Accept: "application/json", "X-Requested-With": "XMLHttpRequest" }
      })
      const data = await response.json()

      if (data.success) {
        this.switchToManualWithOperations(data.operations, part.part_number, part.id)
      } else {
        alert("Failed to copy operations: " + data.error)
        if (input) {
          input.disabled = false
          input.style.backgroundColor = ""
        }
      }
    } catch (error) {
      console.error("Error copying operations:", error)
      alert("An error occurred while copying operations")
      if (input) {
        input.disabled = false
        input.style.backgroundColor = ""
      }
    }
  }

  switchToManualWithOperations(operations, sourcePart, sourcePartId) {
    if (this.hasTreatmentSectionTarget) this.treatmentSectionTarget.style.display = "none"

    // Record the source part so the server can copy treatment metadata.
    if (sourcePartId) {
      let hiddenInput = this.element.querySelector("#source_part_id_field")
      if (!hiddenInput) {
        hiddenInput = document.createElement("input")
        hiddenInput.type = "hidden"
        hiddenInput.name = "source_part_id"
        hiddenInput.id = "source_part_id_field"
        this.element.appendChild(hiddenInput)
      }
      hiddenInput.value = sourcePartId
    }

    const manualSection = document.createElement("div")
    manualSection.className = "bg-white shadow rounded-lg p-6"
    manualSection.innerHTML = `
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-medium text-gray-900">Manual Operations Mode</h3>
        <span class="inline-flex px-3 py-1 text-xs font-semibold rounded-full bg-green-100 text-green-800">
          Copied from: ${sourcePart}
        </span>
      </div>
      <p class="text-sm text-gray-600 mb-6">Operations copied from existing part. You can modify, add, or remove operations below. Changes to operation text are automatically saved when you click away.</p>
      <div class="space-y-1" id="operations-container">
        ${this.generateCopiedOperationsHTML(operations)}
      </div>
    `

    if (this.hasFormActionsTarget) {
      this.formActionsTarget.parentNode.insertBefore(manualSection, this.formActionsTarget)
    }

    if (this.hasManualModeFieldTarget) this.manualModeFieldTarget.value = "true"
    if (this.hasSwitchButtonTarget) this.switchButtonTarget.style.display = "none"
  }

  generateCopiedOperationsHTML(operations) {
    const addButton = (position, label) => `
      <div class="flex justify-center py-2">
        <button type="button" class="add-operation-btn bg-blue-100 hover:bg-blue-200 text-blue-700 px-4 py-2 rounded-lg text-sm border border-blue-300 transition-colors"
                data-insert-position="${position}">
          ${label}
        </button>
      </div>
    `

    const rows = operations
      .map((op, index) => {
        const vatBadge =
          op.vat_numbers && op.vat_numbers.length > 0
            ? `<span class="text-xs text-gray-500">Vats ${op.vat_numbers.join(", ")}</span>`
            : ""
        const upButton =
          index > 0
            ? `<button type="button" class="reorder-up-btn text-blue-600 hover:text-blue-800 text-sm font-medium" data-position="${op.position}" title="Move up">↑</button>`
            : ""
        const downButton =
          index < operations.length - 1
            ? `<button type="button" class="reorder-down-btn text-blue-600 hover:text-blue-800 text-sm font-medium" data-position="${op.position}" title="Move down">↓</button>`
            : ""

        return `
      ${index > 0 ? addButton(op.position, "+ Add Operation Here") : ""}
      <div class="border border-gray-200 rounded-lg p-4 bg-gray-50 operation-item" data-position="${op.position}">
        <div class="flex justify-between items-start mb-3">
          <div class="flex items-center space-x-3">
            <h4 class="font-medium text-gray-900">Operation ${op.position}: ${op.display_name}</h4>
            ${vatBadge}
          </div>
          <div class="flex items-center space-x-2">
            ${upButton}
            ${downButton}
            <button type="button" class="delete-operation-btn text-red-600 hover:text-red-800 text-xl font-bold" data-position="${op.position}" title="Delete this operation">×</button>
          </div>
        </div>
        <textarea name="locked_operations[${op.position}]" rows="3" autocomplete="off"
                  class="operation-textarea mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                  placeholder="Enter operation text..." data-original-value="${op.operation_text}">${op.operation_text}</textarea>
        ${
          op.specifications
            ? `<p class="mt-2 text-xs text-purple-600"><strong>Specifications:</strong> ${op.specifications}</p>`
            : ""
        }
        <div class="flex flex-wrap gap-2 mt-2 text-xs text-gray-500">
          <span class="bg-blue-100 text-blue-800 px-2 py-1 rounded">Type: ${
            op.process_type ? op.process_type.replace(/_/g, " ") : "Manual"
          }</span>
          ${
            op.target_thickness && op.target_thickness > 0
              ? `<span class="bg-yellow-100 text-yellow-800 px-2 py-1 rounded">Target: ${op.target_thickness}μm</span>`
              : ""
          }
          ${op.auto_inserted ? '<span class="bg-gray-100 text-gray-800 px-2 py-1 rounded">Auto-inserted</span>' : ""}
        </div>
        <input type="hidden" name="locked_operations_display_names[${op.position}]" value="${op.display_name}">
      </div>
    `
      })
      .join("")

    return rows + addButton(operations.length + 1, "+ Add Operation at End")
  }
}
