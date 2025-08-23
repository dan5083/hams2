// app/javascript/controllers/ppi_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "selectedOperationsField",
    "operationsContainer",
    "selectedContainer",
    "treatmentCriteriaContainer",
    "specificationField",
    "enpStripMaskBtn",
    "enpStripTypeContainer",
    "enpStripTypeRadio",
    "enpStripTypeField"
  ]

  static values = {
    filterPath: String,
    detailsPath: String,
    previewPath: String,
    csrfToken: String
  }

  connect() {
    console.log("PPI Form controller connected")
    this.selectedOperations = []
    this.treatmentCounts = {
      standard_anodising: 0,
      hard_anodising: 0,
      chromic_anodising: 0,
      chemical_conversion: 0,
      electroless_nickel_plating: 0,
      masking: 0,
      stripping: 0,
      enp_strip_mask: 0
    }
    this.totalTreatments = 0
    this.maxTreatments = 5 // Increased from 3 to 5
    this.enpStripType = 'nitric' // Default ENP strip type
    this.maskingMethods = {} // Store masking method => location pairs
    this.strippingType = null // Store selected stripping type
    this.strippingMethod = null // Store selected stripping method

    this.initializeExistingData()
    this.setupTreatmentButtons()
    this.setupJigDropdownListener()
    this.setupENPStripTypeListener()
  }

  // Initialize with existing selected operations
  initializeExistingData() {
    try {
      const existingData = JSON.parse(this.selectedOperationsFieldTarget.value || '[]')
      this.selectedOperations = existingData
      this.updateSelectedOperations()
      this.checkENPStripAvailability()
    } catch(e) {
      console.error("Error parsing existing operations:", e)
      this.selectedOperations = []
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
      jigSelect.addEventListener('change', () => {
        // Update the preview when jig selection changes
        if (this.selectedOperations.length > 0) {
          this.updateSelectedOperations()
        }
      })
    }
  }

  // Set up ENP strip type radio button listener
  setupENPStripTypeListener() {
    if (this.hasEnpStripTypeRadioTarget) {
      this.enpStripTypeRadioTargets.forEach(radio => {
        radio.addEventListener('change', (e) => {
          this.enpStripType = e.target.value
          this.enpStripTypeFieldTarget.value = this.enpStripType
          console.log(`ENP Strip type changed to: ${this.enpStripType}`)

          // If ENP Strip Mask is already selected, update the operations
          if (this.treatmentCounts.enp_strip_mask > 0) {
            this.updateENPStripMaskOperations()
          }
        })
      })
    }
  }

  // Handle treatment button clicks
  handleTreatmentClick(event) {
    event.preventDefault()
    const button = event.currentTarget
    const treatment = button.dataset.treatment
    const countBadge = button.querySelector('.count-badge')

    // Special handling for ENP Strip Mask
    if (treatment === 'enp_strip_mask') {
      if (this.treatmentCounts.enp_strip_mask === 0) {
        this.selectENPStripMask(button, countBadge)
      }
      return
    }

    // Special handling for masking
    if (treatment === 'masking') {
      if (this.treatmentCounts.masking === 0) {
        this.selectMasking(button, countBadge)
      }
      return
    }

    // Special handling for stripping
    if (treatment === 'stripping') {
      if (this.treatmentCounts.stripping === 0) {
        this.selectStripping(button, countBadge)
      }
      return
    }

    if (this.totalTreatments >= this.maxTreatments) {
      alert(`Maximum ${this.maxTreatments} treatments allowed`)
      return
    }

    if (this.treatmentCounts[treatment] === 0) {
      this.treatmentCounts[treatment] = 1
      this.totalTreatments++
      this.updateButtonAppearance(button, treatment, countBadge)
      this.updateTreatmentCriteria()
      this.checkENPStripAvailability()
    }
  }

  // Select masking treatment
  selectMasking(button, countBadge) {
    if (this.totalTreatments >= this.maxTreatments) {
      alert(`Maximum ${this.maxTreatments} treatments allowed`)
      return
    }

    this.treatmentCounts.masking = 1
    this.totalTreatments++
    this.updateButtonAppearance(button, 'masking', countBadge)
    this.addMaskingOperation()
    this.updateTreatmentCriteria()
  }

  // Select stripping treatment
  selectStripping(button, countBadge) {
    if (this.totalTreatments >= this.maxTreatments) {
      alert(`Maximum ${this.maxTreatments} treatments allowed`)
      return
    }

    this.treatmentCounts.stripping = 1
    this.totalTreatments++
    this.updateButtonAppearance(button, 'stripping', countBadge)
    this.addStrippingOperation()
    this.updateTreatmentCriteria()
  }

  // Add masking operation
  addMaskingOperation() {
    if (!this.selectedOperations.includes('MASKING')) {
      this.selectedOperations.push('MASKING')
      this.updateSelectedOperations()
    }
  }

  // Add stripping operation
  addStrippingOperation() {
    if (!this.selectedOperations.includes('STRIPPING')) {
      this.selectedOperations.push('STRIPPING')
      this.updateSelectedOperations()
    }
  }

  // Select ENP Strip Mask (adds all 5 operations)
  selectENPStripMask(button, countBadge) {
    this.treatmentCounts.enp_strip_mask = 1
    this.updateButtonAppearance(button, 'enp_strip_mask', countBadge)
    this.showENPStripTypeSelection()
    this.addENPStripMaskOperations()
  }

  // Show ENP strip type selection
  showENPStripTypeSelection() {
    if (this.hasEnpStripTypeContainerTarget) {
      this.enpStripTypeContainerTarget.style.display = 'block'
    }
  }

  // Hide ENP strip type selection
  hideENPStripTypeSelection() {
    if (this.hasEnpStripTypeContainerTarget) {
      this.enpStripTypeContainerTarget.style.display = 'none'
    }
  }

  // Add all 5 ENP Strip Mask operations
  addENPStripMaskOperations() {
    const enpStripOperations = this.getENPStripMaskOperationIds(this.enpStripType)

    // Remove any existing ENP Strip Mask operations first
    this.removeENPStripMaskOperations()

    // Add new operations
    enpStripOperations.forEach(opId => {
      if (!this.selectedOperations.includes(opId)) {
        this.selectedOperations.push(opId)
      }
    })

    this.updateSelectedOperations()
    console.log(`Added ENP Strip Mask operations (${this.enpStripType}):`, enpStripOperations)
  }

  // Update ENP Strip Mask operations when type changes
  updateENPStripMaskOperations() {
    if (this.treatmentCounts.enp_strip_mask > 0) {
      this.addENPStripMaskOperations()
    }
  }

  // Remove ENP Strip Mask operations
  removeENPStripMaskOperations() {
    const allENPStripOperations = [
      'ENP_MASK',
      'ENP_MASKING_CHECK',
      'ENP_STRIP_NITRIC',
      'ENP_STRIP_METEX',
      'ENP_STRIP_MASKING',
      'ENP_MASKING_CHECK_FINAL'
    ]

    this.selectedOperations = this.selectedOperations.filter(id =>
      !allENPStripOperations.includes(id)
    )
  }

  // Get operation IDs for ENP Strip Mask sequence
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

  // Check if ENP Strip Mask should be available
  checkENPStripAvailability() {
    const hasENPOperations = this.selectedOperations.some(opId =>
      ['HIGH_PHOS_VANDALLOY_4100', 'MEDIUM_PHOS_NICKLAD_767', 'LOW_PHOS_NICKLAD_ELV_824', 'PTFE_NICKLAD_ICE'].includes(opId)
    )

    if (this.hasEnpStripMaskBtnTarget) {
      if (hasENPOperations) {
        this.enpStripMaskBtnTarget.style.display = 'block'
      } else {
        this.enpStripMaskBtnTarget.style.display = 'none'
        // If ENP Strip Mask was selected but ENP is removed, deselect it
        if (this.treatmentCounts.enp_strip_mask > 0) {
          this.deselectENPStripMask()
        }
      }
    }
  }

  // Deselect ENP Strip Mask
  deselectENPStripMask() {
    this.treatmentCounts.enp_strip_mask = 0
    this.removeENPStripMaskOperations()
    this.hideENPStripTypeSelection()

    // Reset button appearance
    const button = this.enpStripMaskBtnTarget
    const countBadge = button.querySelector('.count-badge')
    this.resetButtonAppearance(button, countBadge)

    this.updateSelectedOperations()
  }

  // Update button visual state
  updateButtonAppearance(button, treatment, countBadge) {
    button.classList.remove('border-gray-300')

    const colors = {
      'standard_anodising': ['border-blue-500', 'bg-blue-50', 'bg-blue-500'],
      'hard_anodising': ['border-purple-500', 'bg-purple-50', 'bg-purple-500'],
      'chromic_anodising': ['border-green-500', 'bg-green-50', 'bg-green-500'],
      'chemical_conversion': ['border-orange-500', 'bg-orange-50', 'bg-orange-500'],
      'electroless_nickel_plating': ['border-indigo-500', 'bg-indigo-50', 'bg-indigo-500'],
      'masking': ['border-teal-500', 'bg-teal-50', 'bg-teal-500'],
      'stripping': ['border-red-500', 'bg-red-50', 'bg-red-500'],
      'enp_strip_mask': ['border-pink-500', 'bg-pink-50', 'bg-pink-500']
    }

    const [borderColor, bgColor, badgeColor] = colors[treatment]
    button.classList.add(borderColor, bgColor)
    countBadge.classList.remove('bg-gray-100')
    countBadge.classList.add(badgeColor, 'text-white')

    // Set count badge text
    if (treatment === 'enp_strip_mask') {
      countBadge.textContent = '5'
    } else {
      countBadge.textContent = '1'
    }
  }

  // Reset button appearance
  resetButtonAppearance(button, countBadge) {
    // Remove all color classes
    const colorClasses = [
      'border-blue-500', 'bg-blue-50', 'bg-blue-500',
      'border-purple-500', 'bg-purple-50', 'bg-purple-500',
      'border-green-500', 'bg-green-50', 'bg-green-500',
      'border-orange-500', 'bg-orange-50', 'bg-orange-500',
      'border-indigo-500', 'bg-indigo-50', 'bg-indigo-500',
      'border-teal-500', 'bg-teal-50', 'bg-teal-500',
      'border-red-500', 'bg-red-50', 'bg-red-500',
      'border-pink-500', 'bg-pink-50', 'bg-pink-500'
    ]

    button.classList.remove(...colorClasses)
    button.classList.add('border-gray-300')

    countBadge.classList.remove('bg-blue-500', 'bg-purple-500', 'bg-green-500', 'bg-orange-500', 'bg-indigo-500', 'bg-teal-500', 'bg-red-500', 'bg-pink-500', 'text-white')
    countBadge.classList.add('bg-gray-100')
    countBadge.textContent = '0'
  }

  // Update treatment criteria section
  updateTreatmentCriteria() {
    const activeTreatments = Object.keys(this.treatmentCounts)
      .filter(t => this.treatmentCounts[t] > 0 && t !== 'enp_strip_mask') // Exclude ENP Strip Mask from criteria

    if (activeTreatments.length === 0) {
      this.treatmentCriteriaContainerTarget.innerHTML =
        '<p class="text-gray-500 text-sm">Select treatment types above to configure criteria</p>'
      return
    }

    this.treatmentCriteriaContainerTarget.innerHTML = activeTreatments
      .map((treatment, index) => this.generateTreatmentHTML(treatment, index))
      .join('')

    this.addSelectEventListeners()
    this.loadChemicalConversionOperations()
    this.loadENPOperations()
    this.loadMaskingOperations()
    this.loadStrippingOperations()
    this.calculatePlatingTime()
  }

  // Generate HTML for each treatment type
  generateTreatmentHTML(treatment, index) {
    const treatmentName = this.formatTreatmentName(treatment)

    switch(treatment) {
      case 'chemical_conversion':
        return this.generateChemicalConversionHTML(treatmentName, index)
      case 'electroless_nickel_plating':
        return this.generateENPHTML(treatmentName, index)
      case 'masking':
        return this.generateMaskingHTML(treatmentName, index)
      case 'stripping':
        return this.generateStrippingHTML(treatmentName, index)
      default:
        return this.generateStandardAnodisingHTML(treatmentName, index, treatment)
    }
  }

  generateMaskingHTML(treatmentName, index) {
    return `
      <div class="border border-teal-200 rounded-lg p-4 bg-teal-50">
        <h4 class="font-medium text-gray-900 mb-3">${treatmentName} Treatment ${index + 1}</h4>
        <p class="text-sm text-gray-600 mb-3">Select masking methods and specify locations for each.</p>

        <div class="space-y-3">
          <div class="flex items-center space-x-4">
            <label class="flex items-center">
              <input type="checkbox" class="masking-method-checkbox form-checkbox text-teal-600" data-method="bungs" data-treatment="masking">
              <span class="ml-2 text-sm text-gray-700">Bungs</span>
            </label>
            <input type="text" class="masking-location-input flex-1 border border-gray-300 rounded-md px-2 py-1 text-sm" data-method="bungs" placeholder="Location (e.g., threads)" disabled>
          </div>

          <div class="flex items-center space-x-4">
            <label class="flex items-center">
              <input type="checkbox" class="masking-method-checkbox form-checkbox text-teal-600" data-method="pc21_polyester_tape" data-treatment="masking">
              <span class="ml-2 text-sm text-gray-700">PC21 - Polyester tape</span>
            </label>
            <input type="text" class="masking-location-input flex-1 border border-gray-300 rounded-md px-2 py-1 text-sm" data-method="pc21_polyester_tape" placeholder="Location (e.g., edges)" disabled>
          </div>

          <div class="flex items-center space-x-4">
            <label class="flex items-center">
              <input type="checkbox" class="masking-method-checkbox form-checkbox text-teal-600" data-method="45_stopping_off_lacquer" data-treatment="masking">
              <span class="ml-2 text-sm text-gray-700">45 Stopping off lacquer</span>
            </label>
            <input type="text" class="masking-location-input flex-1 border border-gray-300 rounded-md px-2 py-1 text-sm" data-method="45_stopping_off_lacquer" placeholder="Location (e.g., critical surfaces)" disabled>
          </div>
        </div>

        <div class="mt-4">
          <h5 class="text-sm font-medium text-gray-700 mb-2">Available Operations</h5>
          <div class="operations-list-${index} space-y-1 max-h-32 overflow-y-auto border border-gray-200 rounded p-2 bg-white">
            <p class="text-gray-500 text-xs">Select masking methods above to see operation</p>
          </div>
        </div>
      </div>
    `
  }

  generateStrippingHTML(treatmentName, index) {
    return `
      <div class="border border-red-200 rounded-lg p-4 bg-red-50">
        <h4 class="font-medium text-gray-900 mb-3">${treatmentName} Treatment ${index + 1}</h4>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Stripping Type</label>
            <select class="stripping-type-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-red-500 focus:border-red-500 sm:text-sm" data-treatment="stripping">
              <option value="">Select stripping type...</option>
              <option value="anodising_stripping">Anodising Stripping</option>
              <option value="enp_stripping">ENP Stripping</option>
            </select>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Stripping Method</label>
            <select class="stripping-method-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-red-500 focus:border-red-500 sm:text-sm" data-treatment="stripping" disabled>
              <option value="">Select method...</option>
            </select>
          </div>
        </div>
        <div class="mt-4">
          <h5 class="text-sm font-medium text-gray-700 mb-2">Available Operations</h5>
          <div class="operations-list-${index} space-y-1 max-h-32 overflow-y-auto border border-gray-200 rounded p-2 bg-white">
            <p class="text-gray-500 text-xs">Select stripping type and method above to see operation</p>
          </div>
        </div>
      </div>
    `
  }

  generateChemicalConversionHTML(treatmentName, index) {
    return `
      <div class="border border-orange-200 rounded-lg p-4 bg-orange-50">
        <h4 class="font-medium text-gray-900 mb-3">${treatmentName} Treatment ${index + 1}</h4>
        <p class="text-sm text-gray-600 mb-3">Chemical conversion operations will be available below - no additional criteria needed.</p>
        <div class="mt-4">
          <h5 class="text-sm font-medium text-gray-700 mb-2">Available Operations</h5>
          <div class="operations-list-${index} space-y-1 max-h-32 overflow-y-auto border border-gray-200 rounded p-2 bg-white">
            <p class="text-gray-500 text-xs">Loading chemical conversion operations...</p>
          </div>
        </div>
      </div>
    `
  }

  generateENPHTML(treatmentName, index) {
    return `
      <div class="border border-indigo-200 rounded-lg p-4 bg-indigo-50">
        <h4 class="font-medium text-gray-900 mb-3">${treatmentName} Treatment ${index + 1}</h4>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Alloy/Material</label>
            <select class="alloy-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm" data-treatment="electroless_nickel_plating">
              <option value="">Select material...</option>
              <option value="steel">Steel</option>
              <option value="stainless_steel">Stainless Steel</option>
              <option value="316_stainless_steel">316 Stainless Steel</option>
              <option value="aluminium">Aluminium</option>
              <option value="copper">Copper</option>
              <option value="brass">Brass</option>
              <option value="2000_series_alloys">2000 Series Alloys</option>
              <option value="cast_aluminium_william_cope">Cast Aluminium (William Cope)</option>
              <option value="mclaren_sta142_procedure_d">McLaren STA142 Procedure D</option>
            </select>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">ENP Type</label>
            <select class="enp-type-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm" data-treatment="electroless_nickel_plating">
              <option value="">Select ENP type...</option>
              <option value="high_phosphorous">High Phosphorous</option>
              <option value="medium_phosphorous">Medium Phosphorous</option>
              <option value="low_phosphorous">Low Phosphorous</option>
              <option value="ptfe_composite">PTFE Composite</option>
            </select>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Target Thickness (μm)</label>
            <input type="number" class="thickness-input mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm" data-treatment="electroless_nickel_plating" placeholder="e.g., 25" min="1" max="100">
            <p class="text-xs text-gray-500 mt-1">Used for time calculation</p>
          </div>
        </div>
        <div class="mt-4">
          <h5 class="text-sm font-medium text-gray-700 mb-2">Available Operations</h5>
          <div class="operations-list-${index} space-y-1 max-h-32 overflow-y-auto border border-gray-200 rounded p-2 bg-white">
            <p class="text-gray-500 text-xs">Select criteria above to see ENP operations</p>
          </div>
        </div>
        <div class="mt-4 p-3 bg-blue-50 border border-blue-200 rounded">
          <h6 class="text-sm font-medium text-blue-800 mb-1">Plating Time Estimate</h6>
          <div class="plating-time-estimate text-sm text-blue-700">
            Enter thickness above to see time estimate
          </div>
        </div>
      </div>
    `
  }

  generateStandardAnodisingHTML(treatmentName, index, treatment) {
    return `
      <div class="border border-gray-200 rounded-lg p-4">
        <h4 class="font-medium text-gray-900 mb-3">${treatmentName} Treatment ${index + 1}</h4>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Alloy</label>
            <select class="alloy-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" data-treatment="${treatment}">
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
            <select class="thickness-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" data-treatment="${treatment}">
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
            <select class="anodic-select mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm" data-treatment="${treatment}">
              <option value="">Select class...</option>
              <option value="class_1">Class 1 (Undyed)</option>
              <option value="class_2">Class 2 (Dyed)</option>
            </select>
          </div>
        </div>
        <div class="mt-4">
          <h5 class="text-sm font-medium text-gray-700 mb-2">Available Operations</h5>
          <div class="operations-list-${index} space-y-1 max-h-32 overflow-y-auto border border-gray-200 rounded p-2 bg-gray-50">
            <p class="text-gray-500 text-xs">Select criteria above to see operations</p>
          </div>
        </div>
      </div>
    `
  }

  // Add event listeners to dynamically created selects
  addSelectEventListeners() {
    const allSelects = this.treatmentCriteriaContainerTarget.querySelectorAll('select')
    const allInputs = this.treatmentCriteriaContainerTarget.querySelectorAll('input')
    const allCheckboxes = this.treatmentCriteriaContainerTarget.querySelectorAll('.masking-method-checkbox')

    allSelects.forEach(select => {
      select.addEventListener('change', (e) => this.filterOperationsForTreatment(e))
    })

    allInputs.forEach(input => {
      input.addEventListener('input', (e) => {
        if (e.target.classList.contains('thickness-input')) {
          this.calculatePlatingTime()
          if (e.target.dataset.treatment === 'electroless_nickel_plating') {
            this.loadENPOperations()
            this.maybeUpdateENPPreview()
          }
        } else if (e.target.classList.contains('masking-location-input')) {
          this.updateMaskingMethods()
        }
        this.filterOperationsForTreatment(e)
      })
    })

    // Special handling for masking checkboxes
    allCheckboxes.forEach(checkbox => {
      checkbox.addEventListener('change', (e) => {
        const method = e.target.dataset.method
        const locationInput = this.treatmentCriteriaContainerTarget.querySelector(`input.masking-location-input[data-method="${method}"]`)

        if (e.target.checked) {
          locationInput.disabled = false
          locationInput.focus()
        } else {
          locationInput.disabled = true
          locationInput.value = ''
        }

        this.updateMaskingMethods()
      })
    })

    // Special handling for stripping type selection
    const strippingTypeSelects = this.treatmentCriteriaContainerTarget.querySelectorAll('.stripping-type-select')
    strippingTypeSelects.forEach(select => {
      select.addEventListener('change', (e) => {
        this.updateStrippingMethodOptions(e.target)
        this.updateStrippingSelection()
      })
    })

    const strippingMethodSelects = this.treatmentCriteriaContainerTarget.querySelectorAll('.stripping-method-select')
    strippingMethodSelects.forEach(select => {
      select.addEventListener('change', (e) => {
        this.updateStrippingSelection()
      })
    })
  }

  // Update masking methods from form inputs
  updateMaskingMethods() {
    const checkboxes = this.treatmentCriteriaContainerTarget.querySelectorAll('.masking-method-checkbox')
    this.maskingMethods = {}

    checkboxes.forEach(checkbox => {
      if (checkbox.checked) {
        const method = checkbox.dataset.method
        const locationInput = this.treatmentCriteriaContainerTarget.querySelector(`input.masking-location-input[data-method="${method}"]`)
        this.maskingMethods[method] = locationInput.value || ''
      }
    })

    console.log('Updated masking methods:', this.maskingMethods)
    this.loadMaskingOperations()
    this.updateSelectedOperations()
  }

  // Update stripping method options based on type
  updateStrippingMethodOptions(typeSelect) {
    const methodSelect = typeSelect.parentElement.parentElement.querySelector('.stripping-method-select')
    const strippingType = typeSelect.value

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
  }

  // Update stripping selection from form inputs
  updateStrippingSelection() {
    const typeSelect = this.treatmentCriteriaContainerTarget.querySelector('.stripping-type-select')
    const methodSelect = this.treatmentCriteriaContainerTarget.querySelector('.stripping-method-select')

    this.strippingType = typeSelect?.value || null
    this.strippingMethod = methodSelect?.value || null

    console.log('Updated stripping selection:', { type: this.strippingType, method: this.strippingMethod })
    this.loadStrippingOperations()
    this.updateSelectedOperations()
  }

  // Check if ENP operations are selected and update preview
  maybeUpdateENPPreview() {
    const hasENPSelected = this.selectedOperations.some(id =>
      id.includes('PHOS') || id.includes('PTFE') || id.includes('NICKLAD') || id.includes('VANDALLOY')
    )
    if (hasENPSelected) {
      this.updateSelectedOperations()
    }
  }

  // Calculate plating time for ENP
  calculatePlatingTime() {
    const activeTreatments = Object.keys(this.treatmentCounts).filter(t => this.treatmentCounts[t] > 0 && !['enp_strip_mask', 'masking', 'stripping'].includes(t))
    const enpIndex = activeTreatments.indexOf('electroless_nickel_plating')

    if (enpIndex === -1) return

    const thicknessInput = this.treatmentCriteriaContainerTarget.querySelector('.thickness-input[data-treatment="electroless_nickel_plating"]')
    const enpTypeSelect = this.treatmentCriteriaContainerTarget.querySelector('.enp-type-select[data-treatment="electroless_nickel_plating"]')
    const timeEstimateDiv = this.treatmentCriteriaContainerTarget.querySelector('.plating-time-estimate')

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

  // Utility method to format treatment names
  formatTreatmentName(treatment) {
    return treatment
      .replace('_anodising', '')
      .replace('_conversion', '')
      .replace('_nickel_plating', '')
      .charAt(0).toUpperCase() +
      treatment
        .replace('_anodising', '')
        .replace('_conversion', '')
        .replace('_nickel_plating', '')
        .slice(1)
  }

  // Load chemical conversion operations
  async loadChemicalConversionOperations() {
    const activeTreatments = Object.keys(this.treatmentCounts).filter(t => this.treatmentCounts[t] > 0 && !['enp_strip_mask', 'masking', 'stripping'].includes(t))
    const chemicalIndex = activeTreatments.indexOf('chemical_conversion')

    if (chemicalIndex === -1) return

    const operationsList = this.element.querySelector(`.operations-list-${chemicalIndex}`)

    try {
      const operations = await this.fetchOperations({ anodising_types: ['chemical_conversion'] })
      this.displayOperationsForTreatment(operations, operationsList, 'chemical_conversion')
    } catch (error) {
      console.error('Error loading chemical conversion operations:', error)
      operationsList.innerHTML = '<p class="text-red-500 text-xs">Error loading operations</p>'
    }
  }

  // Load ENP operations
  async loadENPOperations() {
    const activeTreatments = Object.keys(this.treatmentCounts).filter(t => this.treatmentCounts[t] > 0 && !['enp_strip_mask', 'masking', 'stripping'].includes(t))
    const enpIndex = activeTreatments.indexOf('electroless_nickel_plating')

    if (enpIndex === -1) return

    const operationsList = this.element.querySelector(`.operations-list-${enpIndex}`)
    const thicknessInput = this.treatmentCriteriaContainerTarget.querySelector('.thickness-input[data-treatment="electroless_nickel_plating"]')

    const criteria = { anodising_types: ['electroless_nickel_plating'] }

    if (thicknessInput?.value) {
      criteria.target_thicknesses = [parseFloat(thicknessInput.value)]
    }

    try {
      const operations = await this.fetchOperations(criteria)
      this.displayOperationsForTreatment(operations, operationsList, 'electroless_nickel_plating')
    } catch (error) {
      console.error('Error loading ENP operations:', error)
      operationsList.innerHTML = '<p class="text-red-500 text-xs">Error loading operations</p>'
    }
  }

  // Load masking operations
  async loadMaskingOperations() {
    const activeTreatments = Object.keys(this.treatmentCounts).filter(t => this.treatmentCounts[t] > 0 && !['enp_strip_mask', 'masking', 'stripping'].includes(t))
    const maskingIndex = activeTreatments.indexOf('masking')

    if (maskingIndex === -1) return

    const operationsList = this.element.querySelector(`.operations-list-${maskingIndex}`)

    try {
      const criteria = {
        anodising_types: ['masking'],
        masking_methods: this.maskingMethods
      }
      const operations = await this.fetchOperations(criteria)
      this.displayOperationsForTreatment(operations, operationsList, 'masking')
    } catch (error) {
      console.error('Error loading masking operations:', error)
      operationsList.innerHTML = '<p class="text-red-500 text-xs">Error loading operations</p>'
    }
  }

  // Load stripping operations
  async loadStrippingOperations() {
    const activeTreatments = Object.keys(this.treatmentCounts).filter(t => this.treatmentCounts[t] > 0 && !['enp_strip_mask', 'masking', 'stripping'].includes(t))
    const strippingIndex = activeTreatments.indexOf('stripping')

    if (strippingIndex === -1) return

    const operationsList = this.element.querySelector(`.operations-list-${strippingIndex}`)

    try {
      const criteria = {
        anodising_types: ['stripping'],
        stripping_type: this.strippingType,
        stripping_method: this.strippingMethod
      }
      const operations = await this.fetchOperations(criteria)
      this.displayOperationsForTreatment(operations, operationsList, 'stripping')
    } catch (error) {
      console.error('Error loading stripping operations:', error)
      operationsList.innerHTML = '<p class="text-red-500 text-xs">Error loading operations</p>'
    }
  }

  // Filter operations for treatment
  async filterOperationsForTreatment(event) {
    const select = event.target
    const treatment = select.dataset.treatment

    if (treatment === 'chemical_conversion') return // Already loaded
    if (treatment === 'masking') return // Handled by updateMaskingMethods
    if (treatment === 'stripping') return // Handled by updateStrippingSelection

    const treatmentIndex = Object.keys(this.treatmentCounts)
      .filter(t => this.treatmentCounts[t] > 0 && !['enp_strip_mask', 'masking', 'stripping'].includes(t))
      .indexOf(treatment)
    const operationsList = this.element.querySelector(`.operations-list-${treatmentIndex}`)

    const criteria = this.buildCriteriaFromForm(treatment)

    if (!this.hasCriteria(criteria, treatment)) {
      operationsList.innerHTML = '<p class="text-gray-500 text-xs">Select criteria above to see operations</p>'
      return
    }

    try {
      const operations = await this.fetchOperations(criteria)
      this.displayOperationsForTreatment(operations, operationsList, treatment)
    } catch (error) {
      console.error('Error filtering operations:', error)
      operationsList.innerHTML = '<p class="text-red-500 text-xs">Error loading operations</p>'
    }
  }

  // Build criteria object from form
  buildCriteriaFromForm(treatment) {
    const criteria = { anodising_types: [treatment] }

    if (treatment === 'electroless_nickel_plating') {
      const alloySelect = this.treatmentCriteriaContainerTarget.querySelector(`.alloy-select[data-treatment="${treatment}"]`)
      const enpTypeSelect = this.treatmentCriteriaContainerTarget.querySelector(`.enp-type-select[data-treatment="${treatment}"]`)
      const thicknessInput = this.treatmentCriteriaContainerTarget.querySelector(`.thickness-input[data-treatment="${treatment}"]`)

      if (alloySelect?.value) criteria.alloys = [alloySelect.value]
      if (enpTypeSelect?.value) criteria.enp_types = [enpTypeSelect.value]
      if (thicknessInput?.value) criteria.target_thicknesses = [parseFloat(thicknessInput.value)]
    } else if (treatment === 'masking') {
      criteria.masking_methods = this.maskingMethods
    } else if (treatment === 'stripping') {
      criteria.stripping_type = this.strippingType
      criteria.stripping_method = this.strippingMethod
    } else {
      const alloySelect = this.treatmentCriteriaContainerTarget.querySelector(`.alloy-select[data-treatment="${treatment}"]`)
      const thicknessSelect = this.treatmentCriteriaContainerTarget.querySelector(`.thickness-select[data-treatment="${treatment}"]`)
      const anodicSelect = this.treatmentCriteriaContainerTarget.querySelector(`.anodic-select[data-treatment="${treatment}"]`)

      if (alloySelect?.value) criteria.alloys = [alloySelect.value]
      if (thicknessSelect?.value) criteria.target_thicknesses = [parseFloat(thicknessSelect.value)]
      if (anodicSelect?.value) criteria.anodic_classes = [anodicSelect.value]
    }

    return criteria
  }

  // Check if criteria has been set
  hasCriteria(criteria, treatment) {
    if (treatment === 'electroless_nickel_plating') {
      return true // Always load ENP operations
    } else if (treatment === 'masking') {
      return Object.keys(this.maskingMethods).length > 0
    } else if (treatment === 'stripping') {
      return this.strippingType && this.strippingMethod
    }
    return criteria.alloys?.length || criteria.target_thicknesses?.length || criteria.anodic_classes?.length
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

  // Display operations in container
  displayOperationsForTreatment(operations, container, treatment) {
    if (operations.length === 0) {
      container.innerHTML = '<p class="text-gray-500 text-xs">No matching operations found</p>'
      return
    }

    container.innerHTML = operations.map(op => {
      const displayText = (['chemical_conversion', 'electroless_nickel_plating', 'masking', 'stripping'].includes(treatment)) ?
        op.id.replace(/_/g, ' ') : op.display_name
      const isSelected = this.selectedOperations.includes(op.id)

      return `
        <div class="bg-white border border-gray-200 rounded px-2 py-1 cursor-pointer hover:bg-gray-50 text-xs ${isSelected ? 'opacity-50' : ''}"
             data-operation-id="${op.id}" data-action="click->ppi-form#selectOperation">
          <div class="flex justify-between items-center">
            <span class="font-medium">${displayText}</span>
            <button type="button" class="text-green-600 hover:text-green-800">+</button>
          </div>
          <p class="text-gray-600 mt-1">${op.operation_text}</p>
          ${op.specifications ? `<p class="text-purple-600 text-xs mt-1">${op.specifications}</p>` : ''}
        </div>
      `
    }).join('')
  }

  // Select an operation
  selectOperation(event) {
    const element = event.currentTarget
    const operationId = element.dataset.operationId

    if (this.selectedOperations.includes(operationId)) return
    if (this.selectedOperations.length >= this.maxTreatments && !['MASKING', 'STRIPPING'].includes(operationId)) {
      alert(`Maximum ${this.maxTreatments} operations allowed`)
      return
    }

    this.selectedOperations.push(operationId)
    this.updateSelectedOperations()
    element.classList.add('opacity-50')

    // Check if ENP operations were added to show ENP Strip Mask
    this.checkENPStripAvailability()
  }

  // Remove an operation
  removeOperation(event) {
    const operationId = event.params.operationId

    // Check if this is an ENP Strip Mask operation
    const enpStripOperations = [
      'ENP_MASK', 'ENP_MASKING_CHECK', 'ENP_STRIP_NITRIC',
      'ENP_STRIP_METEX', 'ENP_STRIP_MASKING', 'ENP_MASKING_CHECK_FINAL'
    ]

    if (enpStripOperations.includes(operationId)) {
      // If removing any ENP Strip Mask operation, remove all and deselect the treatment
      this.deselectENPStripMask()
    } else if (operationId === 'MASKING') {
      // Remove masking operation and deselect treatment
      this.deselectMasking()
    } else if (operationId === 'STRIPPING') {
      // Remove stripping operation and deselect treatment
      this.deselectStripping()
    } else {
      // Normal operation removal
      this.selectedOperations = this.selectedOperations.filter(id => id !== operationId)
      this.updateSelectedOperations()

      // Remove opacity from all matching elements
      this.element.querySelectorAll(`[data-operation-id="${operationId}"]`).forEach(el => {
        el.classList.remove('opacity-50')
      })

      // Check ENP Strip availability after removing operations
      this.checkENPStripAvailability()
    }
  }

  // Deselect masking treatment
  deselectMasking() {
    this.treatmentCounts.masking = 0
    this.totalTreatments--
    this.maskingMethods = {}

    this.selectedOperations = this.selectedOperations.filter(id => id !== 'MASKING')

    // Reset button appearance
    const button = this.element.querySelector('[data-treatment="masking"]')
    const countBadge = button.querySelector('.count-badge')
    this.resetButtonAppearance(button, countBadge)

    this.updateTreatmentCriteria()
    this.updateSelectedOperations()
  }

  // Deselect stripping treatment
  deselectStripping() {
    this.treatmentCounts.stripping = 0
    this.totalTreatments--
    this.strippingType = null
    this.strippingMethod = null

    this.selectedOperations = this.selectedOperations.filter(id => id !== 'STRIPPING')

    // Reset button appearance
    const button = this.element.querySelector('[data-treatment="stripping"]')
    const countBadge = button.querySelector('.count-badge')
    this.resetButtonAppearance(button, countBadge)

    this.updateTreatmentCriteria()
    this.updateSelectedOperations()
  }

  // Update selected operations display
  async updateSelectedOperations() {
    this.selectedOperationsFieldTarget.value = JSON.stringify(this.selectedOperations)

    if (this.selectedOperations.length === 0) {
      this.selectedContainerTarget.innerHTML = '<p class="text-gray-500 text-sm">No treatments selected</p>'
      return
    }

    try {
      const requestData = { operation_ids: this.selectedOperations }

      // Add thickness for ENP interpolation
      const thicknessInput = this.treatmentCriteriaContainerTarget.querySelector('.thickness-input[data-treatment="electroless_nickel_plating"]')
      if (thicknessInput?.value) {
        requestData.target_thickness = parseFloat(thicknessInput.value)
      }

      // Add selected jig type for jig interpolation
      const jigSelect = this.element.querySelector('select[name*="selected_jig_type"]')
      if (jigSelect?.value) {
        requestData.selected_jig_type = jigSelect.value
      }

      // Add ENP strip type for ENP Strip Mask operations
      if (this.treatmentCounts.enp_strip_mask > 0) {
        requestData.enp_strip_type = this.enpStripType
      }

      // Add masking methods for masking operations
      if (this.treatmentCounts.masking > 0) {
        requestData.masking_methods = this.maskingMethods
      }

      // Add stripping configuration for stripping operations
      if (this.treatmentCounts.stripping > 0) {
        requestData.stripping_type = this.strippingType
        requestData.stripping_method = this.strippingMethod
      }

      const response = await fetch(this.previewPathValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfTokenValue
        },
        body: JSON.stringify(requestData)
      })

      const data = await response.json()
      const operations = data.operations || []

      this.selectedContainerTarget.innerHTML = operations.map((op, index) => {
        const isAutoInserted = op.auto_inserted
        const isENPStripMask = ['ENP_MASK', 'ENP_MASKING_CHECK', 'ENP_STRIP_NITRIC', 'ENP_STRIP_METEX', 'ENP_STRIP_MASKING', 'ENP_MASKING_CHECK_FINAL'].includes(op.id)
        const isMasking = op.id === 'MASKING'
        const isStripping = op.id === 'STRIPPING'

        let bgColor, textColor, removeButton

        if (isAutoInserted) {
          bgColor = 'bg-gray-100 border border-gray-300'
          textColor = 'italic text-gray-600'
          removeButton = ''
        } else if (isENPStripMask) {
          bgColor = 'bg-pink-100 border border-pink-300'
          textColor = 'text-gray-900'
          removeButton = `<button type="button" class="text-red-600 hover:text-red-800 ml-2" data-action="click->ppi-form#removeOperation" data-ppi-form-operation-id-param="${op.id}">×</button>`
        } else if (isMasking) {
          bgColor = 'bg-teal-100 border border-teal-300'
          textColor = 'text-gray-900'
          removeButton = `<button type="button" class="text-red-600 hover:text-red-800 ml-2" data-action="click->ppi-form#removeOperation" data-ppi-form-operation-id-param="${op.id}">×</button>`
        } else if (isStripping) {
          bgColor = 'bg-red-100 border border-red-300'
          textColor = 'text-gray-900'
          removeButton = `<button type="button" class="text-red-600 hover:text-red-800 ml-2" data-action="click->ppi-form#removeOperation" data-ppi-form-operation-id-param="${op.id}">×</button>`
        } else {
          bgColor = 'bg-blue-100 border border-blue-300'
          textColor = 'text-gray-900'
          removeButton = `<button type="button" class="text-red-600 hover:text-red-800 ml-2" data-action="click->ppi-form#removeOperation" data-ppi-form-operation-id-param="${op.id}">×</button>`
        }

        const autoLabel = isAutoInserted ? '<span class="text-xs text-gray-500 ml-2">(auto-inserted)</span>' :
                          isENPStripMask ? '<span class="text-xs text-pink-600 ml-2">(ENP strip/mask)</span>' :
                          isMasking ? '<span class="text-xs text-teal-600 ml-2">(masking)</span>' :
                          isStripping ? '<span class="text-xs text-red-600 ml-2">(stripping)</span>' : ''

        return `
          <div class="${bgColor} rounded px-3 py-2 flex justify-between items-center" data-operation-id="${op.id}">
            <span class="text-sm ${textColor}">
              <strong>${index + 1}.</strong>
              ${op.display_name}: ${op.operation_text}
              ${autoLabel}
            </span>
            ${removeButton}
          </div>
        `
      }).join('')
    } catch (error) {
      console.error('Error updating selected operations:', error)
      // Fallback to basic display
      this.selectedContainerTarget.innerHTML = '<p class="text-red-500 text-sm">Error loading operation preview</p>'
    }
  }
}
