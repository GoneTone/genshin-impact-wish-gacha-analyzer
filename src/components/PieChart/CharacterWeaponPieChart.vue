<template>
  <div class="col-lg-6">
    <div class="card shadow mb-4">
      <div class="card-header py-3 d-flex flex-row align-items-center justify-content-between">
        <h6 class="m-0 font-weight-bold text-primary">{{ $t("ui.text.wins_pie_chart") }} ({{ $t("ui.text.character") }}/{{ $t("ui.text.weapon") }})</h6>
      </div>
      <div class="card-body">
        <div class="chart-pie pt-4 pb-2">
          <canvas id="characterWeaponPieChart"></canvas>
        </div>
        <div class="mt-4 text-center small">
          <span class="mr-2">
            <i class="fas fa-circle text-bd6932"></i> {{ $t("ui.text.character_wins_count", { count: characterWins.toString() }) }}
          </span>
          <span class="mr-2">
            <i class="fas fa-circle text-a256e1"></i> {{ $t("ui.text.weapon_wins_count", { count: weaponWins.toString() }) }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: 'CharacterWeaponPieChart',
  props: {
    characterWins: {
      type: Number,
      required: true
    },
    weaponWins: {
      type: Number,
      required: true
    }
  },
  data () {
    return {
      characterWeaponPieChart: null
    }
  },
  mounted () {
    this.$nextTick(function () {
      // eslint-disable-next-line no-undef
      Chart.defaults.global.defaultFontFamily = '"HYWenHei-85W", "Default_SC", "Muli", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji"'
      // eslint-disable-next-line no-undef
      Chart.defaults.global.defaultFontColor = '#858796'

      // 中獎數圓餅圖 (角色/武器)
      // eslint-disable-next-line no-new,no-undef
      this.$data.characterWeaponPieChart = new Chart(document.getElementById('characterWeaponPieChart'), {
        type: 'doughnut',
        data: {
          labels: [this.$t('ui.text.count_of_win_by_character'), this.$t('ui.text.count_of_win_by_weapon')],
          datasets: [{
            data: [this.characterWins, this.weaponWins],
            backgroundColor: ['#bd6932', '#a256e1'],
            hoverBorderColor: 'rgba(234, 236, 244, 1)'
          }]
        },
        options: {
          maintainAspectRatio: false,
          tooltips: {
            backgroundColor: 'rgb(255,255,255)',
            bodyFontColor: '#858796',
            borderColor: '#dddfeb',
            borderWidth: 1,
            xPadding: 15,
            yPadding: 15,
            displayColors: false,
            caretPadding: 10
          },
          legend: {
            display: false
          },
          cutoutPercentage: 80
        }
      })
    })
  },
  updated () {
    this.$nextTick(function () {
      this.$data.characterWeaponPieChart.data.datasets.forEach((dataset) => {
        dataset.data = [this.characterWins, this.weaponWins]
      })

      this.$data.characterWeaponPieChart.update()
    })
  }
}
</script>
