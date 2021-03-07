<template>
  <div class="col-lg-6">
    <div class="card shadow mb-4">
      <div class="card-header py-3 d-flex flex-row align-items-center justify-content-between">
        <h6 class="m-0 font-weight-bold text-primary">中獎數圓餅圖 (級別)</h6>
      </div>
      <div class="card-body">
        <div class="chart-pie pt-4 pb-2">
          <canvas id="rankPieChart"></canvas>
        </div>
        <div class="mt-4 text-center small">
          <span class="mr-2">
            <i class="fas fa-circle text-bd6932"></i> 5星中獎數：{{ fiveRankWins.toString() }}
          </span>
          <span class="mr-2">
            <i class="fas fa-circle text-a256e1"></i> 4星中獎數：{{ fourRankWins.toString() }}
          </span>
          <span class="mr-2">
            <i class="fas fa-circle text-8e8e8e"></i> 3星以下中獎數：{{ threeRankWins.toString() }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: 'RankPieChart',
  props: {
    fiveRankWins: {
      type: Number,
      required: true
    },
    fourRankWins: {
      type: Number,
      required: true
    },
    threeRankWins: {
      type: Number,
      required: true
    }
  },
  data () {
    return {
      rankPieChart: null
    }
  },
  mounted () {
    this.$nextTick(function () {
      // eslint-disable-next-line no-undef
      Chart.defaults.global.defaultFontFamily = '"HYWenHei-85W", "Default_SC", "Muli", -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji"'
      // eslint-disable-next-line no-undef
      Chart.defaults.global.defaultFontColor = '#858796'

      // 中獎數圓餅圖 (星級)
      // eslint-disable-next-line no-new,no-undef
      this.$data.rankPieChart = new Chart(document.getElementById('rankPieChart'), {
        type: 'doughnut',
        data: {
          labels: ['5星中獎數', '4星中獎數', '3星以下中獎數'],
          datasets: [{
            data: [this.fiveRankWins, this.fourRankWins, this.threeRankWins],
            backgroundColor: ['#bd6932', '#a256e1', '#8e8e8e'],
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
      this.$data.rankPieChart.data.datasets.forEach((dataset) => {
        dataset.data = [this.fiveRankWins, this.fourRankWins, this.threeRankWins]
      })

      this.$data.rankPieChart.update()
    })
  }
}
</script>
