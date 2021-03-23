<template>
  <div class="container-fluid mt-4">
    <!--suppress HtmlDeprecatedAttribute -->
    <iframe class="w-100" id="iframe" frameborder="0" :src="src" allowfullscreen></iframe>
  </div>
</template>

<script>
export default {
  name: 'IframeView',
  props: {
    src: {
      type: String,
      required: true
    }
  },
  mounted () {
    (function ($) {
      const footer = $('footer')
      const content = $('#content')
      const iframe = $('#iframe')

      iframe.height((content.height() - footer.height()))

      $(window).resize(function () {
        iframe.height(((content.height() - 10) - footer.height()))
      })
      // eslint-disable-next-line no-undef
    })(jQuery)
  }
}
</script>
