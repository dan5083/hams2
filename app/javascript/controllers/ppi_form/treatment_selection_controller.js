// app/javascript/controllers/ppi_form/treatment_selection_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["criteriaContainer"]
  static outlets = ["operations-filter", "enp-calculator"]

  static values = {
    maxTreatments: { type: Number, default: 3 }
  }

  connect() {
    this.treatmentCounts = {
      standard_anodising: 0,
      hard_anodising: 0,
      chromic_anodising: 0,
      chemical_conversion: 0,
      electroless_nickel_plating: 0
    }
    this.totalTreatments = 0
    this.setupTreatmentButtons()
  }

  setupTreatmentButtons() {
    this.element.querySelectorAll('.treatment-btn').forEach(button => {
      button.addEventListener('click', (e) => this.handleTreatmentClick(e))
    })
  }

  handleTreatmentClick(event) {
    event.preventDefault()
    const button = event.currentTarget
    const treatment = button.dataset.treatment
    const countBadge = button.querySelector('.count-badge')

    if (this.totalTreatments >= this.maxTreatmentsValue) {
      alert(`Maximum ${this.maxTreatmentsValue} treatments allowed`)
      return
    }

    if (this.treatmentCounts[treatment] === 0) {
      this.treatmentCounts[treatment] = 1
      this.totalTreatments++
      this.updateButtonAppearance(button, treatment, countBadge)
      this.updateTreatmentCriteria()
      this.notifyTreatmentChanged()
    }
  }

  updateButtonAppearance(button, treatment, countBadge) {
    button.classList.remove('border-gray-300')

    const colors = {
      'standard_anodising': ['border-blue-500', 'bg-blue-50', 'bg-blue-500'],
      'hard_anodising': ['border-purple-500', 'bg-purple-50', 'bg-purple-500'],
      'chromic_anodising': ['border-green-500', 'bg-green-50', 'bg-green-500'],
      'chemical_conversion': ['border-orange-500', 'bg-orange-50', 'bg-orange-500'],
      'electroless_nickel_plating': ['border-indigo-500', 'bg-indigo-50', 'bg-indigo-500']
    }

    const [borderColor, bgColor, badgeColor] = colors[treatment]
    button.classList.add(borderColor, bgColor)
    countBadge.classList.remove('bg-gray-100')
    countBadge.classList.add(badgeColor, 'text-white')
    countBadge.textContent = '1'
  }

  updateTreatmentCriteria() {
    const activeTreatments = this.getActiveTreatments()

    if (activeTreatments.length === 0) {
      this.criteriaContainerTarget.innerHTML =
        '<p class="text-gray-500 text-sm">Select treatment types above to configure criteria</p>'
      return
    }

    this.criteriaContainerTarget.innerHTML = activeTreatments
      .map((treatment, index) => this.generateTreatmentHTML(treatment, index))
      .join('')

    this.addSelectEventListeners()
  }

  generateTreatmentHTML(treatment, index) {
    const treatmentName = this.formatTreatmentName(treatment)

    switch(treatment) {
      case 'chemical_conversion':
        return this.generateChemicalConversionHTML(treatmentName, index)
      case 'electroless_nickel_plating':
        return this.generateENPHTML(treatmentName, index)
      default:
        return this.generateStandardAnodisingHTML(treatmentName, index, treatment)
    }
  }

  generateChemicalConversionHTML(treatmentName, index) {
    return `
      <div class="border border-orange-200 rounded-lg p-4 bg-orange-50" data-treatment-index="${index}">
        <h4 class="font-medium text-gray-900 mb-3">${treatmentName} Treatment ${index + 1}</h4>
        <p class="text-sm text-gray-600 mb-3">Chemical conversion operations will be available below - no additional criteria needed.</p>
        <div class="mt-4">
          <h5 class="text-sm font-medium text-gray-700 mb-2">Available Operations</h5>
          <div class="operations-list space-y-1 max-h-32 overflow-y-auto border border-gray-200 rounded p-2 bg-white" data-treatment="chemical_conversion" data-treatment-index="${index}">
            <p class="text-gray-500 text-xs">Loading chemical conversion operations...</p>
          </div>
        </div>
      </div>
    `
  }

  generateENPHTML(treatmentName, index) {
    return `
      <div class="border border-indigo-200 rounded-lg p-4 bg-indigo-50" data-treatment-index="${index}">
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
          <div class="operations-list space-y-1 max-h-32 overflow-y-auto border border-gray-200 rounded p-2 bg-white" data-treatment="electroless_nickel_plating" data-treatment-index="${index}">
            <p class="text-gray-500 text-xs">Select criteria above to see ENP operations</p>
          </div>
        </div>
        <div class="mt-4 p-3 bg-blue-50 border border-blue-200 rounded">
          <h6 class="text-sm font-medium text-blue-800 mb-1">Plating Time Estimate</h6>
          <div class="plating-time-estimate text-sm text-blue-700" data-enp-calculator-target="timeEstimate">
            Enter thickness above to see time estimate
          </div>
        </div>
      </div>
    `
  }

  generateStandardAnodisingHTML(treatmentName, index, treatment) {
    return `
      <div class="border border-gray-200 rounded-lg p-4" data-treatment-index="${index}">
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
          <div class="operations-list space-y-1 max-h-32 overflow-y-auto border border-gray-200 rounded p-2 bg-gray-50" data-treatment="${treatment}" data-treatment-index="${index}">
            <p class="text-gray-500 text-xs">Select criteria above to see operations</p>
          </div>
        </div>
      </div>
    `
  }

  addSelectEventListeners() {
    const allSelects = this.criteriaContainerTarget.querySelectorAll('select')
    const allInputs = this.criteriaContainerTarget.querySelectorAll('input')

    allSelects.forEach(select => {
      select.addEventListener('change', (e) => this.handleCriteriaChange(e))
    })

    allInputs.forEach(input => {
      input.addEventListener('input', (e) => this.handleCriteriaChange(e))
    })
  }

  handleCriteriaChange(event) {
    this.notifyTreatmentChanged()

    // Special handling for ENP thickness changes
    if (event.target.classList.contains('thickness-input') &&
        event.target.dataset.treatment === 'electroless_nickel_plating') {
      this.notifyENPThicknessChanged(event.target.value)
    }
  }

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

  getActiveTreatments() {
    return Object.keys(this.treatmentCounts).filter(t => this.treatmentCounts[t] > 0)
  }

  getAllCriteria() {
    return this.getActiveTreatments().map(treatment => {
      const treatmentIndex = this.getActiveTreatments().indexOf(treatment)
      return {
        treatment,
        treatmentIndex,
        criteria: this.buildCriteriaForTreatment(treatment)
      }
    })
  }

  buildCriteriaForTreatment(treatment) {
    const criteria = { anodising_types: [treatment] }

    if (treatment === 'electroless_nickel_plating') {
      const alloySelect = this.criteriaContainerTarget.querySelector(`.alloy-select[data-treatment="${treatment}"]`)
      const enpTypeSelect = this.criteriaContainerTarget.querySelector(`.enp-type-select[data-treatment="${treatment}"]`)
      const thicknessInput = this.criteriaContainerTarget.querySelector(`.thickness-input[data-treatment="${treatment}"]`)

      if (alloySelect?.value) criteria.alloys = [alloySelect.value]
      if (enpTypeSelect?.value) criteria.enp_types = [enpTypeSelect.value]
      if (thicknessInput?.value) criteria.target_thicknesses = [parseFloat(thicknessInput.value)]
    } else if (treatment !== 'chemical_conversion') {
      const alloySelect = this.criteriaContainerTarget.querySelector(`.alloy-select[data-treatment="${treatment}"]`)
      const thicknessSelect = this.criteriaContainerTarget.querySelector(`.thickness-select[data-treatment="${treatment}"]`)
      const anodicSelect = this.criteriaContainerTarget.querySelector(`.anodic-select[data-treatment="${treatment}"]`)

      if (alloySelect?.value) criteria.alloys = [alloySelect.value]
      if (thicknessSelect?.value) criteria.target_thicknesses = [parseFloat(thicknessSelect.value)]
      if (anodicSelect?.value) criteria.anodic_classes = [anodicSelect.value]
    }

    return criteria
  }

  getENPThickness() {
    const thicknessInput = this.criteriaContainerTarget.querySelector('.thickness-input[data-treatment="electroless_nickel_plating"]')
    return thicknessInput?.value ? parseFloat(thicknessInput.value) : null
  }

  getENPType() {
    const enpTypeSelect = this.criteriaContainerTarget.querySelector('.enp-type-select[data-treatment="electroless_nickel_plating"]')
    return enpTypeSelect?.value || null
  }

  // Event dispatching to communicate with other controllers
  notifyTreatmentChanged() {
    this.dispatch("treatmentChanged", {
      detail: {
        criteria: this.getAllCriteria(),
        activeTreatments: this.getActiveTreatments()
      }
    })
  }

  notifyENPThicknessChanged(thickness) {
    this.dispatch("enpThicknessChanged", {
      detail: {
        thickness: parseFloat(thickness),
        enpType: this.getENPType()
      }
    })
  }
}
