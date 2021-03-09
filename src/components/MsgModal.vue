<template>
  <div class="modal fade" :id="id" role="dialog" data-backdrop="static" style="z-index: 99999;">
    <div class="modal-dialog modal-xl modal-dialog-centered modal-dialog-scrollable" role="document">
      <div class="modal-content">
        <div class="modal-header">
          <h5 class="modal-title" v-html="title"></h5>
          <button type="button" class="close" data-dismiss="modal" aria-label="Close" @click="this.$store.dispatch('playerAudioEffect', 'close_win')">
            <span aria-hidden="true">×</span>
          </button>
        </div>
        <div class="modal-body" v-html="body"></div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-dismiss="modal" @click="this.$store.dispatch('playerAudioEffect', 'close_win')">關閉訊息</button>
          <button type="button" class="btn btn-primary" :onclick="buttonOnClick" v-html="buttonName" @click="this.$store.dispatch('playerAudioEffect', 'open_win')"></button>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: 'MsgModal',
  props: {
    id: {
      type: String,
      required: true
    },
    title: {
      type: String,
      required: true
    },
    body: {
      type: String,
      default: ''
    },
    buttonName: {
      type: String,
      required: true
    },
    buttonOnClick: {
      type: String,
      required: true
    },
    isShow: {
      type: Boolean,
      required: true
    }
  },
  updated () {
    const _this = this
    ;(function ($) {
      const dom = $(`#${_this.id}`)

      dom.on('click', '.modal-body a', (event) => {
        event.preventDefault()

        _this.$store.dispatch('playerAudioEffect', 'open_win') // 播放音效

        const link = event.target.href
        window.shell.openExternal(link) // 使用外部瀏覽器
      })

      if (_this.isShow) {
        dom.modal() // 顯示訊息
      }
      // eslint-disable-next-line no-undef
    })(jQuery)
  }
}
</script>
