// app/javascript/controllers/parts_form_controller.js
import { Controller } from "@hotwired/stimulus"

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
    "aerospaceDefenseField"
  ]

  static values = {
    filterPath: String,
    detailsPath: String,
    previewPath: String,
    csrfToken: String
  }

  connect() {
    console.log("Parts Form controller connected")

    // Check if we're in locked editing mode by looking for locked operations
    this.isLockedMode = this.element.querySelector('.bg-orange-100.text-orange-800') !== null ||
                       document.querySelector('[data-locked-mode="true"]') !== null

    if (this.isLockedMode) {
      console.log("Parts form in locked editing mode - skipping treatment configuration")
      this.setupLockedMode()
      return
    }

    // Check if we have the required targets for unlocked mode
    if (!this.hasTreatmentsFieldTarget || !this.hasTreatmentsContainerTarget || !this.hasSelectedContainerTarget) {
      console.log("Required targets missing - likely in locked mode or different view")
      return
    }

    // Initialize unlocked mode variables and setup
    this.treatments = []
    this.treatmentCounts = {
      standard_anodising: 0,
      hard_anodising: 0,
      chromic_anodising: 0,
      chemical_conversion: 0,
      electroless_nickel_plating: 0,
      stripping_only: 0
    }
    this.maxTreatments = 5
    this.enpStripType = 'nitric'
    this.enpStripMaskEnabled = false
    this.selectedEnpPreHeatTreatment = 'none'
    this.selectedEnpHeatTreatment = 'none'
    this.aerospaceDefense = false
    this.treatmentIdCounter = 0

    // Available jig types
    this.availableJigTypes = [
      'a secure titanium-to-part assy',
      'Wire (aluminium)',
      'Wire (steel)',
      'Expanding Jig',
      'Large Aluminum Expanding Jig',
      'Rotor Jig',
      'Vertical AllThread Jig',
      'Twisted Double Strap Jig',
      'Long Twisted Double Strap Jig',
      'Double Strap Jig',
      '3 Prong Jig',
      '4 Prong Jig',
      'Flat 3 Prong Jig',
      'Flat 4 Prong Jig',
      'M6 Jig (Metric)',
      'M6 Jig (UNC)',
      'Thin-stem M8 Jig',
      'Thick-stem M8 Jig',
      'Spring Jig',
      'Circular Spring Jig',
      'Aluminum Clamp Jig',
      'Wheel Nut Jig',
      'Muller Jigs',
      'Flat Piston Jig',
      'Upright Piston Jig',
      'Thick Wrap Around Jig',
      'Thin Wrap Around Jig',
      'Monobloc Jig',
      'Hytorque Jig'
    ]

    // Available stripping types and methods - UPDATED FOR E28
    this.availableStrippingTypes = [
      { value: 'anodising_stripping', label: 'Anodising Stripping' },
      { value: 'enp_stripping', label: 'ENP Stripping' }
    ]

    this.availableStrippingMethods = {
      anodising_stripping: [
        { value: 'chromic_phosphoric', label: 'Chromic-Phosphoric Acid' },
        { value: 'E28', label: 'Oxidite E28' }
      ],
      enp_stripping: [
        { value: 'nitric', label: 'Nitric Acid' },
        { value: 'metex_dekote', label: 'Metex Dekote' }
      ]
    }

    // Available local treatments for anodising
    this.availableLocalTreatments = [
      { value: 'none', label: 'No Local Treatment' },
      { value: 'LOCAL_ALOCHROM_1200_PEN', label: 'Alochrom 1200 (Pen)' },
      { value: 'LOCAL_SURTEC_650V_PEN', label: 'SurTec 650V (Pen)' },
      { value: 'LOCAL_PTFE_APPLICATION', label: 'PTFE Application' }
    ]

    this.initializeExistingData()
    this.setupTreatmentButtons()
    this.setupENPPreHeatTreatmentListener()
    this.setupENPHeatTreatmentListener()
    this.setupENPStripTypeListener()
    this.setupENPStripMaskListener()
    this.setupAerospaceDefenseListener()
  }

  // Setup locked mode - minimal functionality for manual editing
  setupLockedMode() {
    console.log("Setting up locked mode - operations are manually editable")

    // Disable any treatment configuration elements that might still be present
    this.element.querySelectorAll('.treatment-btn').forEach(button => {
      button.disabled = true
      button.classList.add('opacity-50', 'cursor-not-allowed')
    })
  }

  // Initialize with existing treatment data (unlocked mode only)
  initializeExistingData() {
    if (this.isLockedMode || !this.hasTreatmentsFieldTarget) return

    try {
      const existingData = JSON.parse(this.treatmentsFieldTarget.value || '[]')
      this.treatments = existingData
      this.updateTreatmentCounts()
      this.renderTreatmentCards()

      // Initialize ENP pre-heat treatment selection
      if (this.hasEnpPreHeatTreatmentFieldTarget && this.hasEnpPreHeatTreatmentSelectTarget) {
        this.selectedEnpPreHeatTreatment = this.enpPreHeatTreatmentFieldTarget.value || 'none'
        this.enpPreHeatTreatmentSelectTarget.value = this.selectedEnpPreHeatTreatment
      }

      // Initialize ENP post-heat treatment selection
      if (this.hasEnpHeatTreatmentFieldTarget && this.hasEnpHeatTreatmentSelectTarget) {
        this.selectedEnpHeatTreatment = this.enpHeatTreatmentFieldTarget.value || 'none'
        this.enpHeatTreatmentSelectTarget.value = this.selectedEnpHeatTreatment
      }

      // Initialize aerospace/defense flag
      if (this.hasAerospaceDefenseCheckboxTarget && this.hasAerospaceDefenseFieldTarget) {
        this.aerospaceDefense = this.aerospaceDefenseCheckboxTarget.checked
        this.aerospaceDefenseFieldTarget.value = this.aerospaceDefense
      }

      // Show ENP options if ENP treatments are present
      this.updateENPOptionsVisibility()
      this.updatePreview()
    } catch(e) {
      console.error("Error parsing existing treatments:", e)
      this.treatments = []
    }
  }

  // Set up treatment button click handlers (unlocked mode only)
  setupTreatmentButtons() {
    if (this.isLockedMode) return

    this.element.querySelectorAll('.treatment-btn').forEach(button => {
      button.addEventListener('click', (e) => this.handleTreatmentClick(e))
    })
  }

  // Set up ENP pre-heat treatment dropdown listener (unlocked mode only)
  setupENPPreHeatTreatmentListener() {
    if (this.isLockedMode || !this.hasEnpPreHeatTreatmentSelectTarget || !this.hasEnpPreHeatTreatmentFieldTarget) return

    this.enpPreHeatTreatmentSelectTarget.addEventListener('change', (e) => {
      this.selectedEnpPreHeatTreatment = e.target.value
      this.enpPreHeatTreatmentFieldTarget.value = this.selectedEnpPreHeatTreatment
      console.log("ENP Pre-Heat Treatment changed to:", this.selectedEnpPreHeatTreatment)
      this.updatePreview()
    })
  }

  // Set up ENP post-heat treatment dropdown listener (unlocked mode only)
  setupENPHeatTreatmentListener() {
    if (this.isLockedMode || !this.hasEnpHeatTreatmentSelectTarget || !this.hasEnpHeatTreatmentFieldTarget) return

    this.enpHeatTreatmentSelectTarget.addEventListener('change', (e) => {
      this.selectedEnpHeatTreatment = e.target.value
      this.enpHeatTreatmentFieldTarget.value = this.selectedEnpHeatTreatment
      console.log("ENP Post-Heat Treatment changed to:", this.selectedEnpHeatTreatment)
      this.updatePreview()
    })
  }

  // Set up ENP strip type radio button listener (unlocked mode only)
  setupENPStripTypeListener() {
    if (this.isLockedMode || !this.hasEnpStripTypeRadioTarget || !this.hasEnpStripTypeFieldTarget) return

    this.enpStripTypeRadioTargets.forEach(radio => {
      radio.addEventListener('change', (e) => {
        this.enpStripType = e.target.value
        this.enpStripTypeFieldTarget.value = this.enpStripType
        this.updatePreview()
      })
    })
  }

  // Set up ENP strip mask checkbox listener (unlocked mode only)
  setupENPStripMaskListener() {
    if (this.isLockedMode || !this.hasEnpStripMaskCheckboxTarget || !this.hasEnpStripMaskFieldTarget) return

    this.enpStripMaskCheckboxTarget.addEventListener('change', (e) => {
      this.enpStripMaskEnabled = e.target.checked
      this.updateENPStripMaskField()
      this.updatePreview()
    })
  }

  // Set up aerospace/defense checkbox listener (unlocked mode only)
  setupAerospaceDefenseListener() {
    if (this.isLockedMode || !this.hasAerospaceDefenseCheckboxTarget || !this.hasAerospaceDefenseFieldTarget) return

    this.aerospaceDefenseCheckboxTarget.addEventListener('change', (e) => {
      this.aerospaceDefense = e.target.checked
      this.aerospaceDefenseFieldTarget.value = this.aerospaceDefense
      this.updatePreview()

      // Provide visual feedback when enabled
      if (this.aerospaceDefense) {
        console.log("Aerospace/Defense mode enabled - foil verification, water break tests and OCV operations will be included")
      }
    })
  }

  // Handle treatment button clicks (unlocked mode only)
  handleTreatmentClick(event) {
    if (this.isLockedMode) return

    event.preventDefault()
    const button = event.currentTarget
    const treatmentType = button.dataset.treatment

    if (this.treatments.length >= this.maxTreatments) {
      alert(`Maximum ${this.maxTreatments} treatments allowed`)
      return
    }

    this.addTreatment(treatmentType, button)
  }

  // Add a new treatment (unlocked mode only)
  addTreatment(treatmentType, button) {
    if (this.isLockedMode) return

    this.treatmentIdCounter++

    const treatment = {
      id: `treatment_${this.treatmentIdCounter}`,
      type: treatmentType,
      operation_id: null,
      selected_alloy: null,
      target_thickness: null,
      selected_jig_type: null,
      stripping_type: treatmentType === 'stripping_only' ? 'anodising_stripping' : null,
      stripping_method: treatmentType === 'stripping_only' ? 'chromic_phosphoric' : null,
      masking_methods: {},
      stripping_enabled: false,
      stripping_type_secondary: 'none',
      stripping_method_secondary: 'none',
      sealing_method: 'none',
      dye_color: 'none',
      ptfe_enabled: false,
      local_treatment_type: 'none'
    }

    this.treatments.push(treatment)
    this.treatmentCounts[treatmentType]++
    this.updateButtonAppearance(button, treatmentType)
    this.renderTreatmentCards()
    this.updateTreatmentsField()
    this.updateENPOptionsVisibility()
  }

  // Update ENP options visibility based on treatment selection (unlocked mode only)
  updateENPOptionsVisibility() {
    if (this.isLockedMode || !this.hasEnpOptionsContainerTarget) return

    const hasENPTreatment = this.treatments.some(t => t.type === 'electroless_nickel_plating')
    this.enpOptionsContainerTarget.style.display = hasENPTreatment ? 'block' : 'none'
  }

  // Update button appearance (unlocked mode only)
  updateButtonAppearance(button, treatmentType) {
    if (this.isLockedMode) return

    const countBadge = button.querySelector('.count-badge')
    button.classList.remove('border-gray-300')

    const colors = {
      'standard_anodising': ['border-blue-500', 'bg-blue-50', 'bg-blue-500'],
      'hard_anodising': ['border-purple-500', 'bg-purple-50', 'bg-purple-500'],
      'chromic_anodising': ['border-green-500', 'bg-green-50', 'bg-green-500'],
      'chemical_conversion': ['border-orange-500', 'bg-orange-50', 'bg-orange-500'],
      'electroless_nickel_plating': ['border-indigo-500', 'bg-indigo-50', 'bg-indigo-500'],
      'stripping_only': ['border-red-500', 'bg-red-50', 'bg-red-500']
    }

    const [borderColor, bgColor, badgeColor] = colors[treatmentType]
    button.classList.add(borderColor, bgColor)
    countBadge.classList.remove('bg-gray-100')
    countBadge.classList.add(badgeColor, 'text-white')
    countBadge.textContent = this.treatmentCounts[treatmentType]
  }

  // Update treatment counts from current treatments array (unlocked mode only)
  updateTreatmentCounts() {
    if (this.isLockedMode) return

    // Reset counts
    Object.keys(this.treatmentCounts).forEach(type => {
      this.treatmentCounts[type] = 0
    })

    // Count current treatments
    this.treatments.forEach(treatment => {
      if (this.treatmentCounts.hasOwnProperty(treatment.type)) {
        this.treatmentCounts[treatment.type]++
      }
    })

    // Update button appearances
    this.element.querySelectorAll('.treatment-btn').forEach(button => {
      const treatmentType = button.dataset.treatment
      const count = this.treatmentCounts[treatmentType]

      if (count > 0) {
        this.updateButtonAppearance(button, treatmentType)
      }
    })
  }

  // Render treatment cards (unlocked mode only)
  renderTreatmentCards() {
    if (this.isLockedMode || !this.hasTreatmentsContainerTarget) return

    if (this.treatments.length === 0) {
      this.treatmentsContainerTarget.innerHTML = '<p class="text-gray-500 text-sm">Select treatments above to configure them</p>'
      return
    }

    this.treatmentsContainerTarget.innerHTML = this.treatments.map((treatment, index) => {
      return this.generateTreatmentCardHTML(treatment, index)
    }).join('')

    // Add event listeners to the newly created elements
    this.addTreatmentCardListeners()
  }

  // Generate HTML for a treatment card (unlocked mode only)
  generateTreatmentCardHTML(treatment, index) {
    if (this.isLockedMode) return ''

    const treatmentName = this.formatTreatmentName(treatment.type)
    const isENP = treatment.type === 'electroless_nickel_plating'
    const isStripOnly = treatment.type === 'stripping_only'

    return `
      <div class="border border-gray-200 rounded-lg p-4 bg-gray-50" data-treatment-id="${treatment.id}">
        <div class="flex justify-between items-center mb-4">
          <h4 class="font-medium text-gray-900">${treatmentName} Treatment ${index + 1}</h4>
          <button type="button" class="text-red-600 hover:text-red-800 text-xl font-bold" data-action="click->parts-form#removeTreatment" data-parts-form-treatment-id-param="${treatment.id}">×</button>
        </div>

        <!-- Jig Selection (Per-treatment) -->
        <div class="mb-4">
          <label class="block text-sm font-medium text-gray-700 mb-2">Jig Type</label>
          <select class="jig-type-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" data-treatment-id="${treatment.id}" required>
            <option value="">Select jig type...</option>
            ${this.availableJigTypes.map(jig =>
              `<option value="${jig}" ${treatment.selected_jig_type === jig ? 'selected' : ''}>${jig}</option>`
            ).join('')}
          </select>
          <p class="mt-1 text-xs text-gray-500">Required for jigging operations in this treatment</p>
        </div>

        ${isStripOnly ? this.generateStripOnlySelectionHTML(treatment) : this.generateOperationSelectionHTML(treatment)}

        <!-- Criteria Selection -->
        ${isStripOnly ? '' : this.generateCriteriaHTML(treatment)}

        <!-- Treatment Modifiers -->
        ${isENP || isStripOnly ? '' : this.generateTreatmentModifiersHTML(treatment)}

        ${isStripOnly ? this.generateStripOnlyModifiersHTML(treatment) : ''}
      </div>
    `
  }

  // Generate strip-only selection HTML
  generateStripOnlySelectionHTML(treatment) {
    return `
      <div class="mb-4">
        <h5 class="text-sm font-medium text-gray-700 mb-3">Strip Configuration</h5>

        <!-- Strip Type Selection -->
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 mb-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Strip Type</label>
            <select class="strip-type-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-red-500 focus:border-red-500 sm:text-sm" data-treatment-id="${treatment.id}">
              ${this.availableStrippingTypes.map(type =>
                `<option value="${type.value}" ${treatment.stripping_type === type.value ? 'selected' : ''}>${type.label}</option>`
              ).join('')}
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Strip Method</label>
            <select class="strip-method-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-red-500 focus:border-red-500 sm:text-sm" data-treatment-id="${treatment.id}">
              ${this.getStrippingMethodsForType(treatment.stripping_type).map(method =>
                `<option value="${method.value}" ${treatment.stripping_method === method.value ? 'selected' : ''}>${method.label}</option>`
              ).join('')}
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

  // Generate operation selection HTML for non-strip-only treatments
  generateOperationSelectionHTML(treatment) {
    return `
      <!-- Operation Selection -->
      <div class="mb-4">
        <label class="block text-sm font-medium text-gray-700 mb-2">Select Operation</label>
        <div class="operations-list space-y-2 max-h-40 overflow-y-auto border border-gray-200 rounded p-3 bg-white">
          <p class="text-gray-500 text-xs">Configure criteria below to see operations</p>
        </div>
      </div>
    `
  }

  // Generate strip-only modifiers HTML
  generateStripOnlyModifiersHTML(treatment) {
    return `
      <div class="border-t border-gray-200 pt-4 mt-4">
        <h5 class="text-sm font-medium text-gray-700 mb-3">Strip Modifiers</h5>

        <div class="space-y-4">
          <!-- Multiple Masking Methods with Individual Locations -->
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">Masking Methods</label>
            <div class="space-y-2">
              <div class="flex items-center space-x-3">
                <label class="flex items-center">
                  <input type="checkbox" class="masking-checkbox rounded border-gray-300 text-teal-600" data-treatment-id="${treatment.id}" data-method="bungs" ${treatment.masking_methods?.bungs !== undefined ? 'checked' : ''}>
                  <span class="ml-2 text-sm text-gray-700">Bungs</span>
                </label>
                <input type="text" class="masking-location flex-1 border border-gray-300 rounded-md px-2 py-1 text-sm" data-treatment-id="${treatment.id}" data-method="bungs" placeholder="Location/notes for bungs..." value="${treatment.masking_methods?.bungs || ''}" ${treatment.masking_methods?.bungs !== undefined ? '' : 'style="display: none;"'}>
              </div>

              <div class="flex items-center space-x-3">
                <label class="flex items-center">
                  <input type="checkbox" class="masking-checkbox rounded border-gray-300 text-teal-600" data-treatment-id="${treatment.id}" data-method="pc21_polyester_tape" ${treatment.masking_methods?.pc21_polyester_tape !== undefined ? 'checked' : ''}>
                  <span class="ml-2 text-sm text-gray-700">PC21 - Polyester Tape</span>
                </label>
                <input type="text" class="masking-location flex-1 border border-gray-300 rounded-md px-2 py-1 text-sm" data-treatment-id="${treatment.id}" data-method="pc21_polyester_tape" placeholder="Location/notes for tape..." value="${treatment.masking_methods?.pc21_polyester_tape || ''}" ${treatment.masking_methods?.pc21_polyester_tape !== undefined ? '' : 'style="display: none;"'}>
              </div>

              <div class="flex items-center space-x-3">
                <label class="flex items-center">
                  <input type="checkbox" class="masking-checkbox rounded border-gray-300 text-teal-600" data-treatment-id="${treatment.id}" data-method="45_stopping_off_lacquer" ${treatment.masking_methods?.['45_stopping_off_lacquer'] !== undefined ? 'checked' : ''}>
                  <span class="ml-2 text-sm text-gray-700">45 Stopping Off Lacquer</span>
                </label>
                <input type="text" class="masking-location flex-1 border border-gray-300 rounded-md px-2 py-1 text-sm" data-treatment-id="${treatment.id}" data-method="45_stopping_off_lacquer" placeholder="Location/notes for lacquer..." value="${treatment.masking_methods?.['45_stopping_off_lacquer'] || ''}" ${treatment.masking_methods?.['45_stopping_off_lacquer'] !== undefined ? '' : 'style="display: none;"'}>
              </div>
            </div>
            <p class="mt-2 text-xs text-gray-500">Masking protects areas that should not be stripped</p>
          </div>
        </div>
      </div>
    `
  }

  // Get stripping methods for a given type
  getStrippingMethodsForType(strippingType) {
    return this.availableStrippingMethods[strippingType] || []
  }

  // Get preview text for stripping operation - UPDATED FOR E28
  getStrippingPreviewText(strippingType, strippingMethod) {
    if (!strippingType || !strippingMethod) return 'Select strip type and method to see preview'

    const methodMap = {
      'anodising_stripping': {
        'chromic_phosphoric': 'Strip anodising in chromic-phosphoric acid solution',
        'E28': 'Strip in Oxidite E28 - wait till fizzing starts and hold for 30 seconds'
      },
      'enp_stripping': {
        'nitric': 'Strip ENP in nitric acid solution 30 to 40 minutes per 25 microns [or until black smut dissolves]',
        'metex_dekote': 'Strip ENP in Metex Dekote at 80 to 90°C, for approximately 20 microns per hour strip rate'
      }
    }

    return methodMap[strippingType]?.[strippingMethod] || 'Strip as specified'
  }

  // Generate criteria selection HTML (unlocked mode only)
  generateCriteriaHTML(treatment) {
    if (this.isLockedMode) return ''

    if (treatment.type === 'chemical_conversion') {
      return ''
    }

    if (treatment.type === 'electroless_nickel_plating') {
      return this.generateENPCriteriaHTML(treatment)
    }

    if (treatment.type === 'chromic_anodising') {
      return this.generateChromicCriteriaHTML(treatment)
    }

    return this.generateAnodisingCriteriaHTML(treatment)
  }

  // Generate chromic criteria HTML (unlocked mode only)
  generateChromicCriteriaHTML(treatment) {
    if (this.isLockedMode) return ''

    return `
      <div class="grid grid-cols-1 gap-4 mb-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Alloy</label>
          <select class="alloy-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-green-500 focus:border-green-500 sm:text-sm" data-treatment-id="${treatment.id}">
            <option value="">Select alloy...</option>
            <option value="general" ${treatment.selected_alloy === 'general' ? 'selected' : ''}>General</option>
            <option value="aluminium" ${treatment.selected_alloy === 'aluminium' ? 'selected' : ''}>Aluminium</option>
            <option value="6000_series" ${treatment.selected_alloy === '6000_series' ? 'selected' : ''}>6000 Series</option>
            <option value="7075" ${treatment.selected_alloy === '7075' ? 'selected' : ''}>7075 (Standard Voltage Only)</option>
            <option value="2024" ${treatment.selected_alloy === '2024' ? 'selected' : ''}>2024</option>
          </select>
          <p class="mt-1 text-xs text-gray-500">Chromic anodising - no class selection needed</p>
        </div>
      </div>
    `
  }

  // Generate ENP criteria HTML (unlocked mode only)
  generateENPCriteriaHTML(treatment) {
    if (this.isLockedMode) return ''

    return `
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-3 mb-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Alloy/Material</label>
          <select class="alloy-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm" data-treatment-id="${treatment.id}">
            <option value="">Select material...</option>
            <option value="steel" ${treatment.selected_alloy === 'steel' ? 'selected' : ''}>Steel</option>
            <option value="stainless_steel" ${treatment.selected_alloy === 'stainless_steel' ? 'selected' : ''}>Stainless Steel</option>
            <option value="316_stainless_steel" ${treatment.selected_alloy === '316_stainless_steel' ? 'selected' : ''}>316 Stainless Steel</option>
            <option value="aluminium" ${treatment.selected_alloy === 'aluminium' ? 'selected' : ''}>Aluminium</option>
            <option value="copper" ${treatment.selected_alloy === 'copper' ? 'selected' : ''}>Copper</option>
            <option value="brass" ${treatment.selected_alloy === 'brass' ? 'selected' : ''}>Brass</option>
            <option value="2000_series_alloys" ${treatment.selected_alloy === '2000_series_alloys' ? 'selected' : ''}>2000 Series Alloys</option>
            <option value="stainless_steel_with_oxides" ${treatment.selected_alloy === 'stainless_steel_with_oxides' ? 'selected' : ''}>Stainless Steel with Oxides</option>
            <option value="copper_sans_electrical_contact" ${treatment.selected_alloy === 'copper_sans_electrical_contact' ? 'selected' : ''}>Copper (Sans Electrical Contact)</option>
            <option value="cope_rolled_aluminium" ${treatment.selected_alloy === 'cope_rolled_aluminium' ? 'selected' : ''}>Cope Rolled Aluminium</option>
            <option value="mclaren_sta142_procedure_d" ${treatment.selected_alloy === 'mclaren_sta142_procedure_d' ? 'selected' : ''}>McLaren STA142 Procedure D</option>
          </select>
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">ENP Type</label>
          <select class="enp-type-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm" data-treatment-id="${treatment.id}">
            <option value="">Select ENP type...</option>
            <option value="high_phosphorous">High Phosphorous</option>
            <option value="medium_phosphorous">Medium Phosphorous</option>
            <option value="low_phosphorous">Low Phosphorous</option>
            <option value="ptfe_composite">PTFE Composite</option>
          </select>
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Target Thickness (μm)</label>
          <input type="number" class="thickness-input mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm" data-treatment-id="${treatment.id}" placeholder="e.g., 25" min="1" max="100" value="${treatment.target_thickness || ''}">
        </div>
      </div>
    `
  }

  // Generate anodising criteria HTML (unlocked mode only)
  generateAnodisingCriteriaHTML(treatment) {
    if (this.isLockedMode) return ''

    return `
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-3 mb-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Alloy</label>
          <select class="alloy-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" data-treatment-id="${treatment.id}">
            <option value="">Select alloy...</option>
            <option value="6000_series">6000 Series</option>
            <option value="7075">7075</option>
            <option value="2014">2014</option>
            <option value="5083">5083</option>
            <option value="titanium">Titanium</option>
            <option value="general">General</option>
          </select>
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Target Thickness (μm)</label>
          <select class="thickness-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" data-treatment-id="${treatment.id}">
            <option value="">Select thickness...</option>
            <option value="5">5μm</option>
            <option value="10">10μm</option>
            <option value="15">15μm</option>
            <option value="20">20μm</option>
            <option value="25">25μm</option>
            <option value="30">30μm</option>
            <option value="40">40μm</option>
            <option value="50">50μm</option>
            <option value="60">60μm</option>
          </select>
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Anodic Class</label>
          <select class="anodic-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" data-treatment-id="${treatment.id}">
            <option value="">Select class...</option>
            <option value="class_1">Class 1 (Undyed)</option>
            <option value="class_2">Class 2 (Dyed)</option>
          </select>
        </div>
      </div>
    `
  }

  // Generate treatment modifiers HTML (unlocked mode only) - UPDATED FOR E28
  generateTreatmentModifiersHTML(treatment) {
    if (this.isLockedMode) return ''

    const anodisingTypes = ['standard_anodising', 'hard_anodising', 'chromic_anodising']
    const showSealing = anodisingTypes.includes(treatment.type)
    const showDye = anodisingTypes.includes(treatment.type)
    const showLocalTreatment = anodisingTypes.includes(treatment.type)

    return `
      <div class="border-t border-gray-200 pt-4 mt-4">
        <h5 class="text-sm font-medium text-gray-700 mb-3">Treatment Modifiers</h5>

        <div class="space-y-4">
          <!-- Multiple Masking Methods with Individual Locations -->
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-2">Masking Methods</label>
            <div class="space-y-2">
              <div class="flex items-center space-x-3">
                <label class="flex items-center">
                  <input type="checkbox" class="masking-checkbox rounded border-gray-300 text-teal-600" data-treatment-id="${treatment.id}" data-method="bungs" ${treatment.masking_methods?.bungs !== undefined ? 'checked' : ''}>
                  <span class="ml-2 text-sm text-gray-700">Bungs</span>
                </label>
                <input type="text" class="masking-location flex-1 border border-gray-300 rounded-md px-2 py-1 text-sm" data-treatment-id="${treatment.id}" data-method="bungs" placeholder="Location/notes for bungs..." value="${treatment.masking_methods?.bungs || ''}" ${treatment.masking_methods?.bungs !== undefined ? '' : 'style="display: none;"'}>
              </div>

              <div class="flex items-center space-x-3">
                <label class="flex items-center">
                  <input type="checkbox" class="masking-checkbox rounded border-gray-300 text-teal-600" data-treatment-id="${treatment.id}" data-method="pc21_polyester_tape" ${treatment.masking_methods?.pc21_polyester_tape !== undefined ? 'checked' : ''}>
                  <span class="ml-2 text-sm text-gray-700">PC21 - Polyester Tape</span>
                </label>
                <input type="text" class="masking-location flex-1 border border-gray-300 rounded-md px-2 py-1 text-sm" data-treatment-id="${treatment.id}" data-method="pc21_polyester_tape" placeholder="Location/notes for tape..." value="${treatment.masking_methods?.pc21_polyester_tape || ''}" ${treatment.masking_methods?.pc21_polyester_tape !== undefined ? '' : 'style="display: none;"'}>
              </div>

              <div class="flex items-center space-x-3">
                <label class="flex items-center">
                  <input type="checkbox" class="masking-checkbox rounded border-gray-300 text-teal-600" data-treatment-id="${treatment.id}" data-method="45_stopping_off_lacquer" ${treatment.masking_methods?.['45_stopping_off_lacquer'] !== undefined ? 'checked' : ''}>
                  <span class="ml-2 text-sm text-gray-700">45 Stopping Off Lacquer</span>
                </label>
                <input type="text" class="masking-location flex-1 border border-gray-300 rounded-md px-2 py-1 text-sm" data-treatment-id="${treatment.id}" data-method="45_stopping_off_lacquer" placeholder="Location/notes for lacquer..." value="${treatment.masking_methods?.['45_stopping_off_lacquer'] || ''}" ${treatment.masking_methods?.['45_stopping_off_lacquer'] !== undefined ? '' : 'style="display: none;"'}>
              </div>
            </div>
          </div>

          <div class="grid grid-cols-1 gap-4 ${showSealing && showDye ? 'sm:grid-cols-3' : (showSealing || showDye ? 'sm:grid-cols-2' : 'sm:grid-cols-1')}">
            <!-- Stripping Method - UPDATED FOR E28 -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Stripping</label>
              <select class="stripping-method-select w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-red-500 focus:border-red-500 sm:text-sm" data-treatment-id="${treatment.id}">
                <option value="none" ${treatment.stripping_method_secondary === 'none' ? 'selected' : ''}>No Stripping</option>
                <option value="chromic_phosphoric" ${treatment.stripping_method_secondary === 'chromic_phosphoric' ? 'selected' : ''}>Chromic-Phosphoric Acid</option>
                <option value="E28" ${treatment.stripping_method_secondary === 'E28' ? 'selected' : ''}>Oxidite E28</option>
                <option value="nitric" ${treatment.stripping_method_secondary === 'nitric' ? 'selected' : ''}>Nitric Acid</option>
                <option value="metex_dekote" ${treatment.stripping_method_secondary === 'metex_dekote' ? 'selected' : ''}>Metex Dekote</option>
              </select>
            </div>

            <!-- Dye Selection (for anodising only) -->
            ${showDye ? `
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Dye Color</label>
              <select class="dye-color-select w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-purple-500 focus:border-purple-500 sm:text-sm" data-treatment-id="${treatment.id}">
                <option value="none" ${treatment.dye_color === 'none' ? 'selected' : ''}>No Dye</option>
                <option value="BLACK_DYE" ${treatment.dye_color === 'BLACK_DYE' ? 'selected' : ''}>Black</option>
                <option value="RED_DYE" ${treatment.dye_color === 'RED_DYE' ? 'selected' : ''}>Red</option>
                <option value="BLUE_DYE" ${treatment.dye_color === 'BLUE_DYE' ? 'selected' : ''}>Blue</option>
                <option value="GOLD_DYE" ${treatment.dye_color === 'GOLD_DYE' ? 'selected' : ''}>Gold</option>
                <option value="GREEN_DYE" ${treatment.dye_color === 'GREEN_DYE' ? 'selected' : ''}>Green</option>
              </select>
            </div>
            ` : ''}

            <!-- Sealing Method (for anodising only) -->
            ${showSealing ? `
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Sealing</label>
              <select class="sealing-method-select w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-purple-500 focus:border-purple-500 sm:text-sm" data-treatment-id="${treatment.id}">
                <option value="none" ${treatment.sealing_method === 'none' ? 'selected' : ''}>No Sealing</option>
                <option value="SODIUM_DICHROMATE_SEAL" ${treatment.sealing_method === 'SODIUM_DICHROMATE_SEAL' ? 'selected' : ''}>Sodium Dichromate Seal</option>
                <option value="OXIDITE_SECO_SEAL" ${treatment.sealing_method === 'OXIDITE_SECO_SEAL' ? 'selected' : ''}>Oxidite SE-CO Seal</option>
                <option value="HOT_WATER_DIP" ${treatment.sealing_method === 'HOT_WATER_DIP' ? 'selected' : ''}>Hot Water Dip</option>
                <option value="HOT_SEAL" ${treatment.sealing_method === 'HOT_SEAL' ? 'selected' : ''}>Hot Seal</option>
                <option value="SURTEC_650V_SEAL" ${treatment.sealing_method === 'SURTEC_650V_SEAL' ? 'selected' : ''}>SurTec 650V Seal</option>
                <option value="DEIONISED_WATER_SEAL" ${treatment.sealing_method === 'DEIONISED_WATER_SEAL' ? 'selected' : ''}>Deionised Water Seal</option>
              </select>
            </div>
            ` : ''}
          </div>

          <!-- PTFE Toggle (for anodising only) -->
          ${showDye ? `
          <div class="pt-2 border-t border-gray-200">
            <label class="flex items-center">
              <input type="checkbox" class="ptfe-checkbox rounded border-gray-300 text-blue-600 shadow-sm focus:border-blue-300 focus:ring focus:ring-offset-0 focus:ring-blue-200 focus:ring-opacity-50" data-treatment-id="${treatment.id}" ${treatment.ptfe_enabled ? 'checked' : ''}>
              <span class="ml-2 text-sm font-medium text-gray-700">Apply PTFE Treatment</span>
            </label>
            <p class="mt-1 text-xs text-gray-500">Anolube treatment applied after sealing</p>
          </div>
          ` : ''}

          <!-- Local Treatment Selection (for anodising only) -->
          ${showLocalTreatment ? `
          <div class="pt-2 border-t border-gray-200">
            <label class="block text-sm font-medium text-gray-700 mb-2">Local Treatment</label>
            <select class="local-treatment-select w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-teal-500 focus:border-teal-500 sm:text-sm" data-treatment-id="${treatment.id}">
              ${this.availableLocalTreatments.map(localTreat =>
                `<option value="${localTreat.value}" ${treatment.local_treatment_type === localTreat.value ? 'selected' : ''}>${localTreat.label}</option>`
              ).join('')}
            </select>
            <p class="mt-1 text-xs text-gray-500">Applied after masking removal operations</p>
          </div>
          ` : ''}
        </div>
      </div>
    `
  }

  // Add event listeners to treatment cards (unlocked mode only)
  addTreatmentCardListeners() {
    if (this.isLockedMode || !this.hasTreatmentsContainerTarget) return

    this.treatmentsContainerTarget.querySelectorAll('select, input').forEach(element => {
      element.addEventListener('change', (e) => this.handleTreatmentChange(e))
      if (element.type === 'text') {
        element.addEventListener('input', (e) => this.handleTreatmentChange(e))
      }
    })

    // Load operations for each non-strip-only treatment
    this.treatments.forEach(treatment => {
      if (treatment.type !== 'stripping_only') {
        this.loadOperationsForTreatment(treatment.id)
      }
    })
  }

  // Handle changes in treatment configuration (unlocked mode only)
  handleTreatmentChange(event) {
    if (this.isLockedMode) return

    const treatmentId = event.target.dataset.treatmentId
    if (!treatmentId) return

    const treatment = this.treatments.find(t => t.id === treatmentId)
    if (!treatment) return

    // Handle jig selection changes
    if (event.target.classList.contains('jig-type-select')) {
      treatment.selected_jig_type = event.target.value
    }

    // Handle strip-only specific changes
    if (event.target.classList.contains('strip-type-select')) {
      treatment.stripping_type = event.target.value
      // Update the strip method dropdown
      this.updateStripMethodDropdown(treatmentId, treatment.stripping_type)
      // Update the preview
      this.updateStripPreview(treatmentId, treatment.stripping_type, treatment.stripping_method)
    }

    if (event.target.classList.contains('strip-method-select')) {
      treatment.stripping_method = event.target.value
      // Update the preview
      this.updateStripPreview(treatmentId, treatment.stripping_type, treatment.stripping_method)
    }

    // Store alloy selection for ENP treatments
    if (event.target.classList.contains('alloy-select') && treatment.type === 'electroless_nickel_plating') {
      treatment.selected_alloy = event.target.value
    }

    // Store alloy selection for chromic treatments
    if (event.target.classList.contains('alloy-select') && treatment.type === 'chromic_anodising') {
      treatment.selected_alloy = event.target.value
    }

    // Store thickness for ENP treatments
    if (event.target.classList.contains('thickness-input') && treatment.type === 'electroless_nickel_plating') {
      treatment.target_thickness = parseFloat(event.target.value) || null
    }

    // Handle masking checkbox changes
    if (event.target.classList.contains('masking-checkbox')) {
      const method = event.target.dataset.method
      const isChecked = event.target.checked

      if (isChecked) {
        treatment.masking_methods[method] = ''
        const locationInput = this.treatmentsContainerTarget.querySelector(`input[data-treatment-id="${treatmentId}"][data-method="${method}"].masking-location`)
        if (locationInput) {
          locationInput.style.display = ''
          locationInput.focus()
        }
      } else {
        delete treatment.masking_methods[method]
        const locationInput = this.treatmentsContainerTarget.querySelector(`input[data-treatment-id="${treatmentId}"][data-method="${method}"].masking-location`)
        if (locationInput) {
          locationInput.style.display = 'none'
          locationInput.value = ''
        }
      }
    }

    // Handle masking location input changes
    if (event.target.classList.contains('masking-location')) {
      const method = event.target.dataset.method
      treatment.masking_methods[method] = event.target.value
    }

    // Handle other modifier changes
    if (event.target.classList.contains('stripping-method-select')) {
      treatment.stripping_method_secondary = event.target.value
      treatment.stripping_enabled = (event.target.value !== 'none')  // ADD THIS LINE
    }

    if (event.target.classList.contains('sealing-method-select')) {
      treatment.sealing_method = event.target.value
    }

    if (event.target.classList.contains('dye-color-select')) {
      treatment.dye_color = event.target.value
    }

    if (event.target.classList.contains('ptfe-checkbox')) {
      treatment.ptfe_enabled = event.target.checked
    }

    if (event.target.classList.contains('local-treatment-select')) {
      treatment.local_treatment_type = event.target.value
    }

    // Update treatment data based on the changed element
    if (event.target.classList.contains('alloy-select') ||
        event.target.classList.contains('thickness-select') ||
        event.target.classList.contains('thickness-input') ||
        event.target.classList.contains('anodic-select') ||
        event.target.classList.contains('enp-type-select')) {

      this.loadOperationsForTreatment(treatmentId)
    }

    this.updateTreatmentsField()
    this.updatePreview()
  }

  // Update strip method dropdown based on selected strip type
  updateStripMethodDropdown(treatmentId, stripType) {
    const card = this.treatmentsContainerTarget.querySelector(`[data-treatment-id="${treatmentId}"]`)
    const methodSelect = card?.querySelector('.strip-method-select')

    if (methodSelect) {
      const methods = this.getStrippingMethodsForType(stripType)
      methodSelect.innerHTML = methods.map(method =>
        `<option value="${method.value}">${method.label}</option>`
      ).join('')

      // Update the treatment data
      const treatment = this.treatments.find(t => t.id === treatmentId)
      if (treatment && methods.length > 0) {
        treatment.stripping_method = methods[0].value
        methodSelect.value = methods[0].value
      }
    }
  }

  // Update strip preview text
  updateStripPreview(treatmentId, stripType, stripMethod) {
    const previewElement = this.treatmentsContainerTarget.querySelector(`[data-strip-preview="${treatmentId}"]`)
    if (previewElement) {
      previewElement.textContent = this.getStrippingPreviewText(stripType, stripMethod)
    }
  }

  // Load operations for a treatment (unlocked mode only)
  async loadOperationsForTreatment(treatmentId) {
    if (this.isLockedMode || !this.hasTreatmentsContainerTarget) return

    const treatment = this.treatments.find(t => t.id === treatmentId)
    if (!treatment || treatment.type === 'stripping_only') return

    const card = this.treatmentsContainerTarget.querySelector(`[data-treatment-id="${treatmentId}"]`)
    if (!card) return

    const operationsList = card.querySelector('.operations-list')
    if (!operationsList) return

    try {
      const criteria = this.buildCriteriaForTreatment(treatment, card)
      const operations = await this.fetchOperations(criteria)
      this.displayOperationsInCard(operations, operationsList, treatmentId)
    } catch (error) {
      console.error('Error loading operations:', error)
      operationsList.innerHTML = '<p class="text-red-500 text-xs">Error loading operations</p>'
    }
  }

  // Build criteria for operation filtering (unlocked mode only)
  buildCriteriaForTreatment(treatment, card) {
    if (this.isLockedMode) return {}

    const criteria = { anodising_types: [treatment.type] }

    if (treatment.type === 'electroless_nickel_plating') {
      const alloySelect = card.querySelector('.alloy-select')
      const enpTypeSelect = card.querySelector('.enp-type-select')
      const thicknessInput = card.querySelector('.thickness-input')

      if (alloySelect?.value) criteria.alloys = [alloySelect.value]
      if (enpTypeSelect?.value) criteria.enp_types = [enpTypeSelect.value]
      if (thicknessInput?.value) {
        const thickness = parseFloat(thicknessInput.value)
        criteria.target_thicknesses = [thickness]
        treatment.target_thickness = thickness
      }
    } else if (treatment.type === 'chromic_anodising') {
      const alloySelect = card.querySelector('.alloy-select')
      if (alloySelect?.value) criteria.alloys = [alloySelect.value]
    } else if (treatment.type !== 'chemical_conversion') {
      const alloySelect = card.querySelector('.alloy-select')
      const thicknessSelect = card.querySelector('.thickness-select')
      const anodicSelect = card.querySelector('.anodic-select')

      if (alloySelect?.value) criteria.alloys = [alloySelect.value]
      if (thicknessSelect?.value) criteria.target_thicknesses = [parseFloat(thicknessSelect.value)]
      if (anodicSelect?.value) criteria.anodic_classes = [anodicSelect.value]
    }

    return criteria
  }

// Update the displayOperationsInCard method in parts_form_controller.js

displayOperationsInCard(operations, container, treatmentId) {
  if (this.isLockedMode) return

  if (operations.length === 0) {
    container.innerHTML = '<p class="text-gray-500 text-xs">No matching operations found</p>'
    return
  }

  container.innerHTML = operations.map(op => `
    <div class="bg-white border border-gray-200 rounded px-2 py-1 cursor-pointer hover:bg-blue-50 text-xs operation-card"
         data-operation-id="${op.id}"
         data-treatment-id="${treatmentId}">
      <div class="flex justify-between items-center">
        <span class="font-medium">${op.display_name || op.id.replace(/_/g, ' ')}</span>
        <span class="select-operation-indicator text-blue-600 text-xs font-medium">Select</span>
      </div>
      <p class="text-gray-600 mt-1">${op.operation_text}</p>
      ${op.specifications ? `<p class="text-purple-600 text-xs mt-1">${op.specifications}</p>` : ''}
    </div>
  `).join('')

  // Add click handlers for the entire operation card
  container.querySelectorAll('.operation-card').forEach(card => {
    card.addEventListener('click', (e) => {
      const operationId = card.dataset.operationId
      const treatmentId = card.dataset.treatmentId
      this.selectOperationForTreatment(operationId, treatmentId)
    })
  })
}

  // Also update the selectOperationForTreatment method to handle the new indicator
  selectOperationForTreatment(operationId, treatmentId) {
    if (this.isLockedMode) return

    const treatment = this.treatments.find(t => t.id === treatmentId)
    if (!treatment) {
      console.error(`Treatment not found: ${treatmentId}`)
      return
    }

    console.log(`Selecting operation ${operationId} for treatment ${treatmentId}`)
    treatment.operation_id = operationId

    // For ENP treatments, store alloy and thickness
    if (treatment.type === 'electroless_nickel_plating') {
      const card = this.treatmentsContainerTarget.querySelector(`[data-treatment-id="${treatmentId}"]`)
      const alloySelect = card?.querySelector('.alloy-select')
      const thicknessInput = card?.querySelector('.thickness-input')

      if (alloySelect && alloySelect.value && !treatment.selected_alloy) {
        treatment.selected_alloy = alloySelect.value
      }

      if (thicknessInput && thicknessInput.value) {
        treatment.target_thickness = parseFloat(thicknessInput.value)
      }
    }

    // For chromic treatments, store alloy
    if (treatment.type === 'chromic_anodising') {
      const card = this.treatmentsContainerTarget.querySelector(`[data-treatment-id="${treatmentId}"]`)
      const alloySelect = card?.querySelector('.alloy-select')

      if (alloySelect && alloySelect.value && !treatment.selected_alloy) {
        treatment.selected_alloy = alloySelect.value
      }
    }

    // Update visual feedback - now targeting the new structure
    if (this.hasTreatmentsContainerTarget) {
      const card = this.treatmentsContainerTarget.querySelector(`[data-treatment-id="${treatmentId}"]`)
      const operationsList = card?.querySelector('.operations-list')

      if (operationsList) {
        // Reset all cards
        operationsList.querySelectorAll('.operation-card').forEach(div => {
          div.classList.remove('bg-blue-100', 'border-blue-400')
          div.classList.add('bg-white', 'border-gray-200')
          const indicator = div.querySelector('.select-operation-indicator')
          if (indicator) {
            indicator.textContent = 'Select'
            indicator.classList.remove('text-green-600', 'font-bold')
            indicator.classList.add('text-blue-600')
          }
        })

        // Highlight selected card
        const selectedDiv = operationsList.querySelector(`[data-operation-id="${operationId}"]`)
        if (selectedDiv) {
          selectedDiv.classList.remove('bg-white', 'border-gray-200')
          selectedDiv.classList.add('bg-blue-100', 'border-blue-400')
          const indicator = selectedDiv.querySelector('.select-operation-indicator')
          if (indicator) {
            indicator.textContent = '✓ Selected'
            indicator.classList.remove('text-blue-600')
            indicator.classList.add('text-green-600', 'font-bold')
          }
        }
      }
    }

    this.updateTreatmentsField()
    this.updatePreview()
  }

  // Remove treatment (unlocked mode only)
  removeTreatment(event) {
    if (this.isLockedMode) return

    const treatmentId = event.params.treatmentId
    const treatmentIndex = this.treatments.findIndex(t => t.id === treatmentId)

    if (treatmentIndex === -1) return

    const treatment = this.treatments[treatmentIndex]
    this.treatmentCounts[treatment.type]--
    this.treatments.splice(treatmentIndex, 1)

    // Reset button if no more of this type
    if (this.treatmentCounts[treatment.type] === 0) {
      const button = this.element.querySelector(`[data-treatment="${treatment.type}"]`)
      if (button) {
        this.resetButtonAppearance(button)
      }
    } else {
      // Update count badge
      const button = this.element.querySelector(`[data-treatment="${treatment.type}"]`)
      if (button) {
        const countBadge = button.querySelector('.count-badge')
        if (countBadge) countBadge.textContent = this.treatmentCounts[treatment.type]
      }
    }

    this.renderTreatmentCards()
    this.updateTreatmentsField()
    this.updateENPOptionsVisibility()
    this.updatePreview()
  }

  // Reset button appearance (unlocked mode only)
  resetButtonAppearance(button) {
    if (this.isLockedMode) return

    const countBadge = button.querySelector('.count-badge')

    // Remove all color classes
    const colorClasses = [
      'border-blue-500', 'bg-blue-50', 'bg-blue-500',
      'border-purple-500', 'bg-purple-50', 'bg-purple-500',
      'border-green-500', 'bg-green-50', 'bg-green-500',
      'border-orange-500', 'bg-orange-50', 'bg-orange-500',
      'border-indigo-500', 'bg-indigo-50', 'bg-indigo-500',
      'border-red-500', 'bg-red-50', 'bg-red-500'
    ]

    button.classList.remove(...colorClasses)
    button.classList.add('border-gray-300')

    if (countBadge) {
      countBadge.classList.remove('bg-blue-500', 'bg-purple-500', 'bg-green-500', 'bg-orange-500', 'bg-indigo-500', 'bg-red-500', 'text-white')
      countBadge.classList.add('bg-gray-100')
      countBadge.textContent = '0'
    }
  }

  // Update ENP strip mask field (unlocked mode only)
  updateENPStripMaskField() {
    if (this.isLockedMode || !this.hasEnpStripMaskFieldTarget) return

    const enpStripMaskOps = this.enpStripMaskEnabled ? this.getENPStripMaskOperationIds(this.enpStripType) : []
    this.enpStripMaskFieldTarget.value = JSON.stringify(enpStripMaskOps)
  }

  // Get ENP Strip Mask operation IDs (unlocked mode only)
  getENPStripMaskOperationIds(stripType) {
    if (this.isLockedMode) return []

    const stripOperation = stripType === 'metex_dekote' ? 'ENP_STRIP_METEX' : 'ENP_STRIP_NITRIC'
    return [
      'ENP_MASK',
      'ENP_MASKING_CHECK',
      stripOperation,
      'ENP_STRIP_MASKING',
      'ENP_MASKING_CHECK_FINAL'
    ]
  }

  // Update treatments field (unlocked mode only)
  updateTreatmentsField() {
    if (this.isLockedMode || !this.hasTreatmentsFieldTarget) return

    this.treatmentsFieldTarget.value = JSON.stringify(this.treatments)
  }

  // Update preview (unlocked mode only)
  async updatePreview() {
    if (this.isLockedMode || !this.hasSelectedContainerTarget) return

    console.log('Updating preview with treatments:', this.treatments, 'ENP Pre-Heat:', this.selectedEnpPreHeatTreatment, 'ENP Post-Heat:', this.selectedEnpHeatTreatment, 'Aerospace/Defense:', this.aerospaceDefense)

    if (this.treatments.length === 0) {
      this.selectedContainerTarget.innerHTML = '<p class="text-gray-500 text-sm">No treatments selected</p>'
      if (this.hasSpecificationFieldTarget) this.specificationFieldTarget.value = ''
      return
    }

    // Filter treatments that have operations selected OR are strip-only
    const treatmentsWithOperations = this.treatments.filter(t => t.operation_id || t.type === 'stripping_only')

    if (treatmentsWithOperations.length === 0) {
      this.selectedContainerTarget.innerHTML = '<p class="text-gray-500 text-sm">Select operations for treatments to see preview</p>'
      if (this.hasSpecificationFieldTarget) this.specificationFieldTarget.value = ''
      return
    }

    // Check if all treatments have jig types selected
    const treatmentsWithoutJigs = treatmentsWithOperations.filter(t => !t.selected_jig_type)
    if (treatmentsWithoutJigs.length > 0) {
      this.selectedContainerTarget.innerHTML = '<p class="text-yellow-600 text-sm">Select jig types for all treatments to see preview</p>'
      if (this.hasSpecificationFieldTarget) this.specificationFieldTarget.value = ''
      return
    }

    try {
      // Convert data structure for server
      const treatmentsData = treatmentsWithOperations.map(treatment => ({
        id: treatment.id,
        type: treatment.type,
        operation_id: treatment.operation_id,
        selected_alloy: treatment.selected_alloy,
        target_thickness: treatment.target_thickness,
        selected_jig_type: treatment.selected_jig_type,
        stripping_type: treatment.stripping_type,
        stripping_method: treatment.stripping_method,
        masking: {
          enabled: Object.keys(treatment.masking_methods || {}).length > 0,
          methods: treatment.masking_methods || {}
        },
        stripping: {
          enabled: treatment.stripping_method_secondary !== 'none',
          type: treatment.stripping_method_secondary !== 'none' ?
            (treatment.stripping_method_secondary === 'nitric' || treatment.stripping_method_secondary === 'metex_dekote' ? 'enp_stripping' : 'anodising_stripping') : null,
          method: treatment.stripping_method_secondary !== 'none' ? treatment.stripping_method_secondary : null
        },
        sealing: {
          enabled: treatment.sealing_method !== 'none',
          type: treatment.sealing_method !== 'none' ? treatment.sealing_method : null
        },
        dye: {
          enabled: treatment.dye_color !== 'none',
          color: treatment.dye_color !== 'none' ? treatment.dye_color : null
        },
        ptfe: {
          enabled: treatment.ptfe_enabled
        },
        local_treatment: {
          enabled: treatment.local_treatment_type !== 'none',
          type: treatment.local_treatment_type !== 'none' ? treatment.local_treatment_type : null
        }
      }))

      const requestData = {
        treatments_data: treatmentsData,
        aerospace_defense: this.aerospaceDefense,
        selected_enp_pre_heat_treatment: this.selectedEnpPreHeatTreatment,
        selected_enp_heat_treatment: this.selectedEnpHeatTreatment
      }

      // Add ENP strip mask if enabled
      if (this.enpStripMaskEnabled) {
        requestData.enp_strip_type = this.enpStripType
        requestData.selected_operations = this.getENPStripMaskOperationIds(this.enpStripType)
      }

      const response = await fetch(this.previewPathValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfTokenValue
        },
        body: JSON.stringify(requestData)
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const data = await response.json()
      const operations = data.operations || []

      if (operations.length === 0) {
        this.selectedContainerTarget.innerHTML = '<p class="text-yellow-600 text-sm">No operations generated - check treatment configuration</p>'
        if (this.hasSpecificationFieldTarget) this.specificationFieldTarget.value = ''
        return
      }

      this.selectedContainerTarget.innerHTML = operations.map((op, index) => {
        const isAutoInserted = op.auto_inserted
        const isWaterBreakTest = op.id === 'WATER_BREAK_TEST'
        const isFoilVerification = op.id === 'FOIL_VERIFICATION'
        const isOcvCheck = op.id === 'OCV_CHECK'
        const isDye = op.id && (op.id.includes('_DYE') || op.display_name?.includes('Dye'))
        const isPreHeatTreatment = op.id && op.id.startsWith('PRE_ENP_HEAT_TREAT')
        const isPostHeatTreatment = op.id && (op.id.startsWith('POST_ENP_HEAT_TREAT') || op.id.includes('ENP_POST_HEAT_TREAT') || op.id.includes('ENP_BAKE'))
        const isLocalTreatment = op.id && op.id.startsWith('LOCAL_')
        const isStripping = op.id === 'STRIPPING' || op.display_name?.includes('Strip')

        let bgColor = 'bg-blue-100 border border-blue-300'
        let textColor = 'text-gray-900'
        let autoLabel = ''

        if (isAutoInserted) {
          bgColor = 'bg-gray-100 border border-gray-300'
          textColor = 'italic text-gray-600'
          autoLabel = '<span class="text-xs text-gray-500 ml-2">(auto-inserted)</span>'
        }

        if (isWaterBreakTest) {
          bgColor = 'bg-red-50 border border-red-200'
          textColor = 'text-red-800'
          autoLabel = '<span class="text-xs text-red-600 ml-2">(requires manual recording)</span>'
        }

        if (isFoilVerification) {
          bgColor = 'bg-yellow-50 border border-yellow-200'
          textColor = 'text-yellow-800'
          autoLabel = '<span class="text-xs text-yellow-600 ml-2">(aerospace/defense verification)</span>'
        }

        if (isOcvCheck) {
          bgColor = 'bg-cyan-50 border border-cyan-200'
          textColor = 'text-cyan-800'
          autoLabel = '<span class="text-xs text-cyan-600 ml-2">(aerospace/defense monitoring)</span>'
        }

        if (isDye) {
          bgColor = 'bg-purple-50 border border-purple-200'
          textColor = 'text-purple-800'
          autoLabel = '<span class="text-xs text-purple-600 ml-2">(dye operation)</span>'
        }

        if (isPreHeatTreatment) {
          bgColor = 'bg-amber-50 border border-amber-200'
          textColor = 'text-amber-800'
          autoLabel = '<span class="text-xs text-amber-600 ml-2">(ENP pre-heat treatment)</span>'
        }

        if (isPostHeatTreatment) {
          bgColor = 'bg-orange-50 border border-orange-200'
          textColor = 'text-orange-800'
          autoLabel = '<span class="text-xs text-orange-600 ml-2">(ENP post-heat treatment)</span>'
        }

        if (isLocalTreatment) {
          bgColor = 'bg-teal-50 border border-teal-200'
          textColor = 'text-teal-800'
          autoLabel = '<span class="text-xs text-teal-600 ml-2">(local treatment)</span>'
        }

        if (isStripping) {
          bgColor = 'bg-red-100 border border-red-300'
          textColor = 'text-red-900'
          autoLabel = '<span class="text-xs text-red-600 ml-2">(strip-only treatment)</span>'
        }

        return `
          <div class="${bgColor} rounded px-3 py-2">
            <span class="text-sm ${textColor}">
              <strong>${index + 1}.</strong>
              ${op.display_name}: ${isOcvCheck ? op.operation_text.replace(/\n/g, '<br>') : op.operation_text}
              ${autoLabel}
            </span>
          </div>
        `
      }).join('')

    } catch (error) {
      console.error('Error updating preview:', error)
      this.selectedContainerTarget.innerHTML = '<p class="text-red-500 text-sm">Error loading preview</p>'
    }
  }

  // Fetch operations from server (unlocked mode only)
  async fetchOperations(criteria) {
    if (this.isLockedMode) return []

    const response = await fetch(this.filterPathValue, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.csrfTokenValue
      },
      body: JSON.stringify(criteria)
    })

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`)
    }

    return await response.json()
  }

  // Format treatment name (unlocked mode only)
  formatTreatmentName(treatmentType) {
    if (this.isLockedMode) return ''

    const nameMap = {
      'stripping_only': 'Strip Only',
      'standard_anodising': 'Standard Anodising',
      'hard_anodising': 'Hard Anodising',
      'chromic_anodising': 'Chromic Anodising',
      'chemical_conversion': 'Chemical Conversion',
      'electroless_nickel_plating': 'Electroless Nickel Plating'
    }

    return nameMap[treatmentType] || treatmentType
      .replace('_anodising', '')
      .replace('_conversion', '')
      .replace('_nickel_plating', '')
      .split('_')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ')
  }
}
