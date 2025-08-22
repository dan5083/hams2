// app/javascript/controllers/ppi_form/enp_calculator_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["timeEstimate"]

  connect() {
    // Listen for ENP thickness changes from treatment selection controller
    this.element.addEventListener("treatment-selection:enpThicknessChanged", (event) => {
      this.handleThicknessChanged(event.detail)
    })
  }

  handleThicknessChanged(detail) {
    const { thickness, enpType } = detail
    this.calculateAndDisplayTime(thickness, enpType)
  }

  calculateAndDisplayTime(thickness, enpType) {
    if (!this.hasTimeEstimateTarget) return

    if (thickness && thickness > 0 && enpType) {
      const timeData = this.getENPTimeData(enpType)
      const { minTimeHours, maxTimeHours, avgTimeHours } = this.calculateTimeRange(thickness, timeData)

      this.timeEstimateTarget.innerHTML = `
        <div class="space-y-1">
          <div><strong>${timeData.typeName}</strong></div>
          <div>Time range: <strong>${this.formatTime(minTimeHours)} - ${this.formatTime(maxTimeHours)}</strong></div>
          <div>Average: <strong>${this.formatTime(avgTimeHours)}</strong></div>
          <div class="text-xs text-blue-600">Rate: ${timeData.minRate}-${timeData.maxRate} μm/hour at 82-91°C</div>
        </div>
      `
    } else if (thickness && thickness > 0) {
      this.timeEstimateTarget.innerHTML = 'Select ENP type above for accurate time estimate'
    } else {
      this.timeEstimateTarget.innerHTML = 'Enter thickness and select ENP type for time estimate'
    }
  }

  getENPTimeData(enpType) {
    const rates = {
      'high_phosphorous': {
        minRate: 12.0,
        maxRate: 14.1,
        typeName: 'High Phos (Vandalloy 4100)'
      },
      'medium_phosphorous': {
        minRate: 13.3,
        maxRate: 17.1,
        typeName: 'Medium Phos (Nicklad 767)'
      },
      'low_phosphorous': {
        minRate: 6.8,
        maxRate: 18.2,
        typeName: 'Low Phos (Nicklad ELV 824)'
      },
      'ptfe_composite': {
        minRate: 5.0,
        maxRate: 11.0,
        typeName: 'PTFE Composite (Nicklad Ice)'
      }
    }
    return rates[enpType] || {
      minRate: 12.0,
      maxRate: 15.0,
      typeName: 'General ENP'
    }
  }

  calculateTimeRange(thickness, timeData) {
    const minTimeHours = thickness / timeData.maxRate
    const maxTimeHours = thickness / timeData.minRate
    const avgTimeHours = (minTimeHours + maxTimeHours) / 2
    return { minTimeHours, maxTimeHours, avgTimeHours }
  }

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

  // Public method for other controllers to call
  calculateTime(thickness, enpType) {
    if (!thickness || !enpType) return null

    const timeData = this.getENPTimeData(enpType)
    return this.calculateTimeRange(thickness, timeData)
  }

  // Public method to get formatted time string
  getFormattedTime(thickness, enpType) {
    const timeRange = this.calculateTime(thickness, enpType)
    if (!timeRange) return null

    const { avgTimeHours } = timeRange
    return this.formatTime(avgTimeHours)
  }
}
