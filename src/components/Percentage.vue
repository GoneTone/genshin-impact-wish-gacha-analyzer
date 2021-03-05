<template>
  <div class="col-xl-4 col-md-6 mb-4">
    <div :class="`card border-left-${color} shadow h-100 py-2`">
      <div class="card-body">
        <div class="row no-gutters align-items-center">
          <div class="col mr-2">
            <div :class="`text-xs font-weight-bold text-${color} text-uppercase mb-1`">
              {{ title }}
            </div>
            <div class="h5 mb-0 font-weight-bold text-gray-800">{{ percentage.toString() }}%</div>
          </div>
          <div class="col-auto">
            <i class="fas fa-percent fa-2x text-gray-300"></i>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: 'Percentage',
  props: {
    title: {
      type: String,
      required: true
    },
    color: {
      type: String,
      required: true
    },
    percentage: {
      type: Number,
      required: true
    }
  }
}
</script>
