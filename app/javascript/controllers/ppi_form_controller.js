// app/javascript/controllers/ppi_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "treatmentsField",
    "treatmentsContainer",
    "selectedContainer",
    "specificationField",
    "enpStripTypeContainer",
    "enpStripTypeRadio",
    "enpStripTypeField",
    "enpStripMaskCheckbox",
    "enpStripMaskField"
  ]

  static values = {
    filterPath: String,
    detailsPath: String,
    previewPath: String,
    csrfToken: String
  }

  connect() {
    console.log("PPI Form controller connected")
    this.treatments = []
    this.treatmentCounts = {
      standard_anodising: 0,
      hard_anodising: 0,
      chromic_anodising: 0,
      chemical_conversion: 0,
      electroless_nickel_plating: 0
    }
    this.maxTreatments = 5
    this.enpStripType = 'nitric'
    this.enpStripMaskEnabled = false
    this.treatmentIdCounter = 0

    this.initializeExistingData()
    this.setupTreatmentButtons()
    this.setupJigDropdownListener()
    this.setupENPStripTypeListener()
    this.setupENPStripMaskListener()
  }

  // Initialize with existing treatment data
  initializeExistingData() {
    try {
      const existingData = JSON.parse(this.treatmentsFieldTarget.value || '[]')
      this.treatments = existingData
      this.updateTreatmentCounts()
      this.renderTreatmentCards()
      this.updatePreview()
    } catch(e) {
      console.error("Error parsing existing treatments:", e)
      this.treatments = []
    }
  }

  // Set up treatment button click handlers
  setupTreatmentButtons() {
    this.element.querySelectorAll('.treatment-btn').forEach(button => {
      button.addEventListener('click', (e) => this.handleTreatmentClick(e))
    })
  }

  // Set up jig dropdown change listener
  setupJigDropdownListener() {
    const jigSelect = this.element.querySelector('select[name*="selected_jig_type"]')
    if (jigSelect) {
      jigSelect.addEventListener('change', () => this.updatePreview())
    }
  }

  // Set up ENP strip type radio button listener
  setupENPStripTypeListener() {
    if (this.hasEnpStripTypeRadioTarget) {
      this.enpStripTypeRadioTargets.forEach(radio => {
        radio.addEventListener('change', (e) => {
          this.enpStripType = e.target.value
          this.enpStripTypeFieldTarget.value = this.enpStripType
          this.updatePreview()
        })
      })
    }
  }

  // Set up ENP strip mask checkbox listener
  setupENPStripMaskListener() {
    if (this.hasEnpStripMaskCheckboxTarget) {
      this.enpStripMaskCheckboxTarget.addEventListener('change', (e) => {
        this.enpStripMaskEnabled = e.target.checked
        this.updateENPStripMaskField()
        this.updatePreview()
      })
    }
  }

  // Handle treatment button clicks
  handleTreatmentClick(event) {
    event.preventDefault()
    const button = event.currentTarget
    const treatmentType = button.dataset.treatment

    if (this.treatments.length >= this.maxTreatments) {
      alert(`Maximum ${this.maxTreatments} treatments allowed`)
      return
    }

    this.addTreatment(treatmentType, button)
  }

  // Add a new treatment
  addTreatment(treatmentType, button) {
    this.treatmentIdCounter++

    const treatment = {
      id: `treatment_${this.treatmentIdCounter}`,
      type: treatmentType,
      operation_id: null,
      selected_alloy: null, // For ENP treatments
      masking: {
        enabled: false,
        methods: {}
      },
      stripping: {
        enabled: false,
        type: null,
        method: null
      },
      sealing: {
        enabled: false,
        type: null
      }
    }

    this.treatments.push(treatment)
    this.treatmentCounts[treatmentType]++
    this.updateButtonAppearance(button, treatmentType)
    this.renderTreatmentCards()
    this.updateTreatmentsField()
  }

  // Update button appearance
  updateButtonAppearance(button, treatmentType) {
    const countBadge = button.querySelector('.count-badge')
    button.classList.remove('border-gray-300')

    const colors = {
      'standard_anodising': ['border-blue-500', 'bg-blue-50', 'bg-blue-500'],
      'hard_anodising': ['border-purple-500', 'bg-purple-50', 'bg-purple-500'],
      'chromic_anodising': ['border-green-500', 'bg-green-50', 'bg-green-500'],
      'chemical_conversion': ['border-orange-500', 'bg-orange-50', 'bg-orange-500'],
      'electroless_nickel_plating': ['border-indigo-500', 'bg-indigo-50', 'bg-indigo-500']
    }

    const [borderColor, bgColor, badgeColor] = colors[treatmentType]
    button.classList.add(borderColor, bgColor)
    countBadge.classList.remove('bg-gray-100')
    countBadge.classList.add(badgeColor, 'text-white')
    countBadge.textContent = this.treatmentCounts[treatmentType]

    // Show ENP options if ENP selected
    if (treatmentType === 'electroless_nickel_plating' && this.hasEnpStripTypeContainerTarget) {
      this.enpStripTypeContainerTarget.style.display = 'block'
    }
  }

  // Update treatment counts from current treatments array
  updateTreatmentCounts() {
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

  // Render treatment cards
  renderTreatmentCards() {
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

  // Generate HTML for a treatment card
  generateTreatmentCardHTML(treatment, index) {
    const treatmentName = this.formatTreatmentName(treatment.type)
    const isENP = treatment.type === 'electroless_nickel_plating'

    return `
      <div class="border border-gray-200 rounded-lg p-4 bg-gray-50" data-treatment-id="${treatment.id}">
        <div class="flex justify-between items-center mb-4">
          <h4 class="font-medium text-gray-900">${treatmentName} Treatment ${index + 1}</h4>
          <button type="button" class="text-red-600 hover:text-red-800" data-action="click->ppi-form#removeTreatment" data-ppi-form-treatment-id-param="${treatment.id}">×</button>
        </div>

        <!-- Operation Selection -->
        <div class="mb-4">
          <label class="block text-sm font-medium text-gray-700 mb-2">Select Operation</label>
          <div class="operations-list space-y-2 max-h-40 overflow-y-auto border border-gray-200 rounded p-3 bg-white">
            <p class="text-gray-500 text-xs">Configure criteria below to see operations</p>
          </div>
        </div>

        <!-- Criteria Selection -->
        ${this.generateCriteriaHTML(treatment)}

        <!-- Sub-selections (not for ENP) -->
        ${isENP ? '' : this.generateSubSelectionsHTML(treatment)}
      </div>
    `
  }

  // Generate criteria selection HTML
  generateCriteriaHTML(treatment) {
    if (treatment.type === 'chemical_conversion') {
      return '' // Chemical conversion needs no criteria
    }

    if (treatment.type === 'electroless_nickel_plating') {
      return this.generateENPCriteriaHTML(treatment)
    }

    return this.generateAnodisingCriteriaHTML(treatment)
  }

  // Generate ENP criteria HTML
  generateENPCriteriaHTML(treatment) {
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
            <option value="cast_aluminium_william_cope" ${treatment.selected_alloy === 'cast_aluminium_william_cope' ? 'selected' : ''}>Cast Aluminium (William Cope)</option>
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
          <input type="number" class="thickness-input mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm" data-treatment-id="${treatment.id}" placeholder="e.g., 25" min="1" max="100">
        </div>
      </div>

      <div class="mt-4 p-3 bg-blue-50 border border-blue-200 rounded">
        <h6 class="text-sm font-medium text-blue-800 mb-1">Plating Time Estimate</h6>
        <div class="plating-time-estimate text-sm text-blue-700" data-treatment-id="${treatment.id}">
          Enter thickness and select ENP type above to see time estimate
        </div>
      </div>
    `
  }

  // Generate anodising criteria HTML
  generateAnodisingCriteriaHTML(treatment) {
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

  // Generate sub-selections HTML (masking, stripping, sealing)
  generateSubSelectionsHTML(treatment) {
    const anodisingTypes = ['standard_anodising', 'hard_anodising', 'chromic_anodising']
    const showSealing = anodisingTypes.includes(treatment.type)

    return `
      <div class="border-t border-gray-200 pt-4 mt-4">
        <h5 class="text-sm font-medium text-gray-700 mb-3">Treatment Modifiers</h5>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-${showSealing ? '3' : '2'}">
          <!-- Masking -->
          <div>
            <label class="flex items-center mb-2">
              <input type="checkbox" class="masking-checkbox form-checkbox text-teal-600" data-treatment-id="${treatment.id}" ${treatment.masking.enabled ? 'checked' : ''}>
              <span class="ml-2 text-sm font-medium text-gray-700">Masking</span>
            </label>
            <div class="masking-methods space-y-2" style="display: ${treatment.masking.enabled ? 'block' : 'none'}">
              <div class="flex items-center space-x-2">
                <input type="checkbox" class="masking-method-checkbox" data-method="bungs" data-treatment-id="${treatment.id}">
                <span class="text-xs text-gray-600">Bungs</span>
                <input type="text" class="masking-location-input flex-1 text-xs border border-gray-300 rounded px-1 py-1" data-method="bungs" placeholder="Location" disabled>
              </div>
              <div class="flex items-center space-x-2">
                <input type="checkbox" class="masking-method-checkbox" data-method="pc21_polyester_tape" data-treatment-id="${treatment.id}">
                <span class="text-xs text-gray-600">PC21 Tape</span>
                <input type="text" class="masking-location-input flex-1 text-xs border border-gray-300 rounded px-1 py-1" data-method="pc21_polyester_tape" placeholder="Location" disabled>
              </div>
              <div class="flex items-center space-x-2">
                <input type="checkbox" class="masking-method-checkbox" data-method="45_stopping_off_lacquer" data-treatment-id="${treatment.id}">
                <span class="text-xs text-gray-600">45 Lacquer</span>
                <input type="text" class="masking-location-input flex-1 text-xs border border-gray-300 rounded px-1 py-1" data-method="45_stopping_off_lacquer" placeholder="Location" disabled>
              </div>
            </div>
          </div>

          <!-- Stripping -->
          <div>
            <label class="flex items-center mb-2">
              <input type="checkbox" class="stripping-checkbox form-checkbox text-red-600" data-treatment-id="${treatment.id}" ${treatment.stripping.enabled ? 'checked' : ''}>
              <span class="ml-2 text-sm font-medium text-gray-700">Stripping</span>
            </label>
            <div class="stripping-options space-y-2" style="display: ${treatment.stripping.enabled ? 'block' : 'none'}">
              <select class="stripping-type-select w-full text-xs border border-gray-300 rounded px-2 py-1" data-treatment-id="${treatment.id}">
                <option value="">Select type...</option>
                <option value="anodising_stripping">Anodising Stripping</option>
                <option value="enp_stripping">ENP Stripping</option>
              </select>
              <select class="stripping-method-select w-full text-xs border border-gray-300 rounded px-2 py-1" data-treatment-id="${treatment.id}" disabled>
                <option value="">Select method...</option>
              </select>
            </div>
          </div>

          <!-- Sealing (only for anodising) -->
          ${showSealing ? `
          <div>
            <label class="flex items-center mb-2">
              <input type="checkbox" class="sealing-checkbox form-checkbox text-purple-600" data-treatment-id="${treatment.id}" ${treatment.sealing.enabled ? 'checked' : ''}>
              <span class="ml-2 text-sm font-medium text-gray-700">Sealing</span>
            </label>
            <div class="sealing-options" style="display: ${treatment.sealing.enabled ? 'block' : 'none'}">
              <select class="sealing-type-select w-full text-xs border border-gray-300 rounded px-2 py-1" data-treatment-id="${treatment.id}">
                <option value="">Select sealing...</option>
                <option value="HOT_SEAL">Hot Seal</option>
                <option value="SODIUM_DICHROMATE_SEAL">Sodium Dichromate Seal</option>
                <option value="OXIDITE_SECO_SEAL">Oxidite SE-CO Seal</option>
                <option value="HOT_WATER_DIP">Hot Water Dip</option>
                <option value="SURTEC_650V_SEAL">SurTec 650V Seal</option>
                <option value="DEIONISED_WATER_SEAL">Deionised Water Seal</option>
              </select>
            </div>
          </div>
          ` : ''}
        </div>
      </div>
    `
  }

  // Add event listeners to treatment cards
  addTreatmentCardListeners() {
    this.treatmentsContainerTarget.querySelectorAll('select, input').forEach(element => {
      element.addEventListener('change', (e) => this.handleTreatmentChange(e))
      if (element.type === 'text') {
        element.addEventListener('input', (e) => this.handleTreatmentChange(e))
      }
    })

    // Special handling for masking checkboxes
    this.treatmentsContainerTarget.querySelectorAll('.masking-checkbox').forEach(checkbox => {
      checkbox.addEventListener('change', (e) => this.toggleMaskingOptions(e))
    })

    this.treatmentsContainerTarget.querySelectorAll('.stripping-checkbox').forEach(checkbox => {
      checkbox.addEventListener('change', (e) => this.toggleStrippingOptions(e))
    })

    this.treatmentsContainerTarget.querySelectorAll('.sealing-checkbox').forEach(checkbox => {
      checkbox.addEventListener('change', (e) => this.toggleSealingOptions(e))
    })

    this.treatmentsContainerTarget.querySelectorAll('.masking-method-checkbox').forEach(checkbox => {
      checkbox.addEventListener('change', (e) => this.toggleMaskingMethodInput(e))
    })

    this.treatmentsContainerTarget.querySelectorAll('.stripping-type-select').forEach(select => {
      select.addEventListener('change', (e) => this.updateStrippingMethods(e))
    })

    // Load operations for each treatment
    this.treatments.forEach(treatment => {
      this.loadOperationsForTreatment(treatment.id)
    })
  }

  // Handle changes in treatment configuration
  handleTreatmentChange(event) {
    const treatmentId = event.target.dataset.treatmentId
    if (!treatmentId) return

    const treatment = this.treatments.find(t => t.id === treatmentId)
    if (!treatment) return

    // Store alloy selection for ENP treatments
    if (event.target.classList.contains('alloy-select') && treatment.type === 'electroless_nickel_plating') {
      treatment.selected_alloy = event.target.value
      console.log(`Updated ENP alloy for treatment ${treatmentId}:`, treatment.selected_alloy)
    }

    // Update treatment data based on the changed element
    if (event.target.classList.contains('alloy-select') ||
        event.target.classList.contains('thickness-select') ||
        event.target.classList.contains('thickness-input') ||
        event.target.classList.contains('anodic-select') ||
        event.target.classList.contains('enp-type-select')) {

      // For ENP, also update time calculation
      if (treatment.type === 'electroless_nickel_plating') {
        this.calculateENPPlatingTime(treatmentId)
      }

      this.loadOperationsForTreatment(treatmentId)
    }

    // Update masking methods
    if (event.target.classList.contains('masking-location-input')) {
      this.updateTreatmentMaskingMethods(treatmentId)
    }

    // Update stripping configuration
    if (event.target.classList.contains('stripping-method-select')) {
      this.updateTreatmentStrippingConfig(treatmentId)
    }

    // Update sealing configuration
    if (event.target.classList.contains('sealing-type-select')) {
      this.updateTreatmentSealingConfig(treatmentId)
    }

    this.updateTreatmentsField()
    this.updatePreview()
  }

  // Toggle masking options visibility
  toggleMaskingOptions(event) {
    const treatmentId = event.target.dataset.treatmentId
    const treatment = this.treatments.find(t => t.id === treatmentId)
    if (!treatment) return

    const card = event.target.closest('[data-treatment-id]')
    const maskingMethods = card.querySelector('.masking-methods')

    treatment.masking.enabled = event.target.checked
    maskingMethods.style.display = event.target.checked ? 'block' : 'none'

    if (!event.target.checked) {
      treatment.masking.methods = {}
      // Uncheck all method checkboxes
      card.querySelectorAll('.masking-method-checkbox').forEach(cb => {
        cb.checked = false
        const input = card.querySelector(`input[data-method="${cb.dataset.method}"]`)
        if (input) {
          input.disabled = true
          input.value = ''
        }
      })
    }

    this.updateTreatmentsField()
    this.updatePreview()
  }

  // Toggle stripping options visibility
  toggleStrippingOptions(event) {
    const treatmentId = event.target.dataset.treatmentId
    const treatment = this.treatments.find(t => t.id === treatmentId)
    if (!treatment) return

    const card = event.target.closest('[data-treatment-id]')
    const strippingOptions = card.querySelector('.stripping-options')

    treatment.stripping.enabled = event.target.checked
    strippingOptions.style.display = event.target.checked ? 'block' : 'none'

    if (!event.target.checked) {
      treatment.stripping.type = null
      treatment.stripping.method = null
      card.querySelectorAll('.stripping-type-select, .stripping-method-select').forEach(select => {
        select.value = ''
      })
    }

    this.updateTreatmentsField()
    this.updatePreview()
  }

  // Toggle sealing options visibility
  toggleSealingOptions(event) {
    const treatmentId = event.target.dataset.treatmentId
    const treatment = this.treatments.find(t => t.id === treatmentId)
    if (!treatment) return

    const card = event.target.closest('[data-treatment-id]')
    const sealingOptions = card.querySelector('.sealing-options')

    treatment.sealing.enabled = event.target.checked
    sealingOptions.style.display = event.target.checked ? 'block' : 'none'

    if (!event.target.checked) {
      treatment.sealing.type = null
      card.querySelector('.sealing-type-select').value = ''
    }

    this.updateTreatmentsField()
    this.updatePreview()
  }

  // Toggle individual masking method input
  toggleMaskingMethodInput(event) {
    const method = event.target.dataset.method
    const card = event.target.closest('[data-treatment-id]')
    const input = card.querySelector(`input.masking-location-input[data-method="${method}"]`)

    if (input) {
      input.disabled = !event.target.checked
      if (!event.target.checked) {
        input.value = ''
      }
    }

    this.updateTreatmentMaskingMethods(event.target.dataset.treatmentId)
  }

  // Update stripping methods based on type
  updateStrippingMethods(event) {
    const card = event.target.closest('[data-treatment-id]')
    const methodSelect = card.querySelector('.stripping-method-select')
    const strippingType = event.target.value

    methodSelect.innerHTML = '<option value="">Select method...</option>'
    methodSelect.disabled = !strippingType

    if (strippingType === 'anodising_stripping') {
      methodSelect.innerHTML += `
        <option value="chromic_phosphoric">Chromic-Phosphoric Acid</option>
        <option value="sulphuric_sodium_hydroxide">Sulphuric Acid + Sodium Hydroxide</option>
      `
    } else if (strippingType === 'enp_stripping') {
      methodSelect.innerHTML += `
        <option value="nitric">Nitric Acid</option>
        <option value="metex_dekote">Metex Dekote</option>
      `
    }

    this.updateTreatmentStrippingConfig(event.target.dataset.treatmentId)
  }

  // Update treatment masking methods
  updateTreatmentMaskingMethods(treatmentId) {
    const treatment = this.treatments.find(t => t.id === treatmentId)
    if (!treatment) return

    const card = this.treatmentsContainerTarget.querySelector(`[data-treatment-id="${treatmentId}"]`)
    const methods = {}

    card.querySelectorAll('.masking-method-checkbox:checked').forEach(checkbox => {
      const method = checkbox.dataset.method
      const locationInput = card.querySelector(`input.masking-location-input[data-method="${method}"]`)
      methods[method] = locationInput ? locationInput.value : ''
    })

    treatment.masking.methods = methods
    this.updateTreatmentsField()
    this.updatePreview()
  }

  // Update treatment stripping configuration
  updateTreatmentStrippingConfig(treatmentId) {
    const treatment = this.treatments.find(t => t.id === treatmentId)
    if (!treatment) return

    const card = this.treatmentsContainerTarget.querySelector(`[data-treatment-id="${treatmentId}"]`)
    const typeSelect = card.querySelector('.stripping-type-select')
    const methodSelect = card.querySelector('.stripping-method-select')

    treatment.stripping.type = typeSelect ? typeSelect.value : null
    treatment.stripping.method = methodSelect ? methodSelect.value : null

    this.updateTreatmentsField()
    this.updatePreview()
  }

  // Update treatment sealing configuration
  updateTreatmentSealingConfig(treatmentId) {
    const treatment = this.treatments.find(t => t.id === treatmentId)
    if (!treatment) return

    const card = this.treatmentsContainerTarget.querySelector(`[data-treatment-id="${treatmentId}"]`)
    const sealingSelect = card.querySelector('.sealing-type-select')

    treatment.sealing.type = sealingSelect ? sealingSelect.value : null

    this.updateTreatmentsField()
    this.updatePreview()
  }

  // Load operations for a treatment
  async loadOperationsForTreatment(treatmentId) {
    const treatment = this.treatments.find(t => t.id === treatmentId)
    if (!treatment) return

    const card = this.treatmentsContainerTarget.querySelector(`[data-treatment-id="${treatmentId}"]`)
    const operationsList = card.querySelector('.operations-list')

    try {
      const criteria = this.buildCriteriaForTreatment(treatment, card)
      const operations = await this.fetchOperations(criteria)
      this.displayOperationsInCard(operations, operationsList, treatmentId)
    } catch (error) {
      console.error('Error loading operations:', error)
      operationsList.innerHTML = '<p class="text-red-500 text-xs">Error loading operations</p>'
    }
  }

  // Build criteria for operation filtering
  buildCriteriaForTreatment(treatment, card) {
    const criteria = { anodising_types: [treatment.type] }

    if (treatment.type === 'electroless_nickel_plating') {
      const alloySelect = card.querySelector('.alloy-select')
      const enpTypeSelect = card.querySelector('.enp-type-select')
      const thicknessInput = card.querySelector('.thickness-input')

      if (alloySelect?.value) criteria.alloys = [alloySelect.value]
      if (enpTypeSelect?.value) criteria.enp_types = [enpTypeSelect.value]
      if (thicknessInput?.value) criteria.target_thicknesses = [parseFloat(thicknessInput.value)]
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

  // Display operations in card
  displayOperationsInCard(operations, container, treatmentId) {
    if (operations.length === 0) {
      container.innerHTML = '<p class="text-gray-500 text-xs">No matching operations found</p>'
      return
    }

    container.innerHTML = operations.map(op => `
      <div class="bg-white border border-gray-200 rounded px-2 py-1 cursor-pointer hover:bg-blue-50 text-xs" data-operation-id="${op.id}" data-treatment-id="${treatmentId}">
        <div class="flex justify-between items-center">
          <span class="font-medium">${op.display_name || op.id.replace(/_/g, ' ')}</span>
          <button type="button" class="select-operation-btn text-blue-600 hover:text-blue-800" data-operation-id="${op.id}" data-treatment-id="${treatmentId}">Select</button>
        </div>
        <p class="text-gray-600 mt-1">${op.operation_text}</p>
        ${op.specifications ? `<p class="text-purple-600 text-xs mt-1">${op.specifications}</p>` : ''}
      </div>
    `).join('')

    // Add click handlers for operation selection
    container.querySelectorAll('.select-operation-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation()
        this.selectOperationForTreatment(e.target.dataset.operationId, e.target.dataset.treatmentId)
      })
    })
  }

  // Select operation for treatment
  selectOperationForTreatment(operationId, treatmentId) {
    const treatment = this.treatments.find(t => t.id === treatmentId)
    if (!treatment) {
      console.error(`Treatment not found: ${treatmentId}`)
      return
    }

    console.log(`Selecting operation ${operationId} for treatment ${treatmentId}`)
    treatment.operation_id = operationId

    // For ENP treatments, also store the selected alloy if not already stored
    if (treatment.type === 'electroless_nickel_plating') {
      const card = this.treatmentsContainerTarget.querySelector(`[data-treatment-id="${treatmentId}"]`)
      const alloySelect = card.querySelector('.alloy-select')
      if (alloySelect && alloySelect.value && !treatment.selected_alloy) {
        treatment.selected_alloy = alloySelect.value
        console.log(`Stored ENP alloy for treatment ${treatmentId}:`, treatment.selected_alloy)
      }
    }

    // Update visual feedback
    const card = this.treatmentsContainerTarget.querySelector(`[data-treatment-id="${treatmentId}"]`)
    const operationsList = card.querySelector('.operations-list')

    operationsList.querySelectorAll('[data-operation-id]').forEach(div => {
      div.classList.remove('bg-blue-100')
      const btn = div.querySelector('.select-operation-btn')
      if (btn) btn.textContent = 'Select'
    })

    const selectedDiv = operationsList.querySelector(`[data-operation-id="${operationId}"]`)
    if (selectedDiv) {
      selectedDiv.classList.add('bg-blue-100')
      const btn = selectedDiv.querySelector('.select-operation-btn')
      if (btn) btn.textContent = 'Selected'
    }

    console.log(`Treatment after selection:`, treatment)
    this.updateTreatmentsField()
    this.updatePreview()
  }

  // Remove treatment
  removeTreatment(event) {
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

      // Hide ENP options if no more ENP treatments
      if (treatment.type === 'electroless_nickel_plating' && this.hasEnpStripTypeContainerTarget) {
        this.enpStripTypeContainerTarget.style.display = 'none'
      }
    } else {
      // Update count badge
      const button = this.element.querySelector(`[data-treatment="${treatment.type}"]`)
      if (button) {
        const countBadge = button.querySelector('.count-badge')
        countBadge.textContent = this.treatmentCounts[treatment.type]
      }
    }

    this.renderTreatmentCards()
    this.updateTreatmentsField()
    this.updatePreview()
  }

  // Reset button appearance
  resetButtonAppearance(button) {
    const countBadge = button.querySelector('.count-badge')

    // Remove all color classes
    const colorClasses = [
      'border-blue-500', 'bg-blue-50', 'bg-blue-500',
      'border-purple-500', 'bg-purple-50', 'bg-purple-500',
      'border-green-500', 'bg-green-50', 'bg-green-500',
      'border-orange-500', 'bg-orange-50', 'bg-orange-500',
      'border-indigo-500', 'bg-indigo-50', 'bg-indigo-500'
    ]

    button.classList.remove(...colorClasses)
    button.classList.add('border-gray-300')

    countBadge.classList.remove('bg-blue-500', 'bg-purple-500', 'bg-green-500', 'bg-orange-500', 'bg-indigo-500', 'text-white')
    countBadge.classList.add('bg-gray-100')
    countBadge.textContent = '0'
  }

  // Update ENP strip mask field
  updateENPStripMaskField() {
    const enpStripMaskOps = this.enpStripMaskEnabled ? this.getENPStripMaskOperationIds(this.enpStripType) : []
    this.enpStripMaskFieldTarget.value = JSON.stringify(enpStripMaskOps)
  }

  // Get ENP Strip Mask operation IDs
  getENPStripMaskOperationIds(stripType) {
    const stripOperation = stripType === 'metex_dekote' ? 'ENP_STRIP_METEX' : 'ENP_STRIP_NITRIC'
    return [
      'ENP_MASK',
      'ENP_MASKING_CHECK',
      stripOperation,
      'ENP_STRIP_MASKING',
      'ENP_MASKING_CHECK_FINAL'
    ]
  }

  // Update treatments field
  updateTreatmentsField() {
    this.treatmentsFieldTarget.value = JSON.stringify(this.treatments)
  }

  // Update preview
  async updatePreview() {
    console.log('Updating preview with treatments:', this.treatments)

    if (this.treatments.length === 0) {
      this.selectedContainerTarget.innerHTML = '<p class="text-gray-500 text-sm">No treatments selected</p>'
      this.specificationFieldTarget.value = ''
      return
    }

    // Filter treatments that have operations selected
    const treatmentsWithOperations = this.treatments.filter(t => t.operation_id)
    console.log('Treatments with operations:', treatmentsWithOperations)

    if (treatmentsWithOperations.length === 0) {
      this.selectedContainerTarget.innerHTML = '<p class="text-gray-500 text-sm">Select operations for treatments to see preview</p>'
      this.specificationFieldTarget.value = ''
      return
    }

    try {
      const requestData = {
        treatments_data: treatmentsWithOperations
      }

      // Add jig type
      const jigSelect = this.element.querySelector('select[name*="selected_jig_type"]')
      if (jigSelect?.value) {
        requestData.selected_jig_type = jigSelect.value
      }

      // Add ENP strip mask if enabled
      if (this.enpStripMaskEnabled) {
        requestData.enp_strip_type = this.enpStripType
        requestData.selected_operations = this.getENPStripMaskOperationIds(this.enpStripType)
      }

      console.log('Sending preview request:', requestData)

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
      console.log('Preview response:', data)
      const operations = data.operations || []

      if (operations.length === 0) {
        this.selectedContainerTarget.innerHTML = '<p class="text-yellow-600 text-sm">No operations generated - check treatment configuration</p>'
        this.specificationFieldTarget.value = ''
        return
      }

      this.selectedContainerTarget.innerHTML = operations.map((op, index) => {
        const isAutoInserted = op.auto_inserted
        const bgColor = isAutoInserted ? 'bg-gray-100 border border-gray-300' : 'bg-blue-100 border border-blue-300'
        const textColor = isAutoInserted ? 'italic text-gray-600' : 'text-gray-900'
        const autoLabel = isAutoInserted ? '<span class="text-xs text-gray-500 ml-2">(auto-inserted)</span>' : ''

        return `
          <div class="${bgColor} rounded px-3 py-2">
            <span class="text-sm ${textColor}">
              <strong>${index + 1}.</strong>
              ${op.display_name}: ${op.operation_text}
              ${autoLabel}
            </span>
          </div>
        `
      }).join('')

      // Update specification
      const specification = operations.map((op, index) => `Operation ${index + 1}: ${op.operation_text}`).join('\n\n')
      this.specificationFieldTarget.value = specification

    } catch (error) {
      console.error('Error updating preview:', error)
      this.selectedContainerTarget.innerHTML = '<p class="text-red-500 text-sm">Error loading preview</p>'
    }
  }

  // Fetch operations from server
  async fetchOperations(criteria) {
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

  // Format treatment name
  formatTreatmentName(treatmentType) {
    return treatmentType
      .replace('_anodising', '')
      .replace('_conversion', '')
      .replace('_nickel_plating', '')
      .split('_')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ')
  }

  // Calculate ENP plating time
  calculateENPPlatingTime(treatmentId) {
    const card = this.treatmentsContainerTarget.querySelector(`[data-treatment-id="${treatmentId}"]`)
    if (!card) return

    const thicknessInput = card.querySelector('.thickness-input')
    const enpTypeSelect = card.querySelector('.enp-type-select')
    const timeEstimateDiv = card.querySelector('.plating-time-estimate')

    if (!thicknessInput || !timeEstimateDiv || !enpTypeSelect) return

    const thickness = parseFloat(thicknessInput.value)
    const enpType = enpTypeSelect.value

    if (thickness && thickness > 0 && enpType) {
      const timeData = this.getENPTimeData(enpType)
      const { minTimeHours, maxTimeHours, avgTimeHours } = this.calculateTimeRange(thickness, timeData)

      timeEstimateDiv.innerHTML = `
        <div class="space-y-1">
          <div><strong>${timeData.typeName}</strong></div>
          <div>Time range: <strong>${this.formatTime(minTimeHours)} - ${this.formatTime(maxTimeHours)}</strong></div>
          <div>Average: <strong>${this.formatTime(avgTimeHours)}</strong></div>
          <div class="text-xs text-blue-600">Rate: ${timeData.minRate}-${timeData.maxRate} μm/hour at 82-91°C</div>
        </div>
      `
    } else if (thickness && thickness > 0) {
      timeEstimateDiv.innerHTML = 'Select ENP type above for accurate time estimate'
    } else {
      timeEstimateDiv.innerHTML = 'Enter thickness and select ENP type for time estimate'
    }
  }

  // Get ENP deposition rates by type
  getENPTimeData(enpType) {
    const rates = {
      'high_phosphorous': { minRate: 12.0, maxRate: 14.1, typeName: 'High Phos (Vandalloy 4100)' },
      'medium_phosphorous': { minRate: 13.3, maxRate: 17.1, typeName: 'Medium Phos (Nicklad 767)' },
      'low_phosphorous': { minRate: 6.8, maxRate: 18.2, typeName: 'Low Phos (Nicklad ELV 824)' },
      'ptfe_composite': { minRate: 5.0, maxRate: 11.0, typeName: 'PTFE Composite (Nicklad Ice)' }
    }
    return rates[enpType] || { minRate: 12.0, maxRate: 15.0, typeName: 'General ENP' }
  }

  // Calculate time range from thickness and rates
  calculateTimeRange(thickness, timeData) {
    const minTimeHours = thickness / timeData.maxRate
    const maxTimeHours = thickness / timeData.minRate
    const avgTimeHours = (minTimeHours + maxTimeHours) / 2
    return { minTimeHours, maxTimeHours, avgTimeHours }
  }

  // Format time display
  formatTime(hours) {
    if (hours < 1) {
      return `${Math.round(hours * 60)} min`
    } else if (hours < 2) {
      const h = Math.floor(hours)
      const m = Math.round((hours - h) * 60)
      return `${h}h ${m}m`
    } else {
      return `${hours.toFixed(1)}h`
    }
  }
}
