<template>
  <ul class="navbar-nav bg-gradient-primary sidebar sidebar-dark accordion" id="accordionSidebar">
    <a class="sidebar-brand d-flex align-items-center justify-content-center">
      <div class="sidebar-brand-icon">
        <!--suppress CheckImageSize -->
        <img class="img-fluid" src="../../build/icons/256x256.png" width="64" alt="Icon">
      </div>
      <div class="sidebar-brand-text mx-3" style="text-transform: none;">{{ this.$store.getters.configs.app.name }} v{{ this.$store.getters.configs.app.version }}</div>
    </a>

    <hr class="sidebar-divider my-0">

    <li class="nav-item">
      <span style="display: block; padding: 0.5rem 1rem; color: #dddfeb">UID：{{ this.$store.getters.datas.playerUID }}</span>
    </li>

    <hr class="sidebar-divider">

    <div class="sidebar-heading">
      綜合
    </div>

    <router-link to="/" v-slot="{ href, navigate, isActive }" custom>
      <li :class="['nav-item', isActive && 'active']">
        <a :class="['nav-link']" :href="href" @click="navigate">
          <i class="fas fa-fw fa-chart-pie"></i>
          <span>綜合數據圖表</span>
        </a>
      </li>
    </router-link>

    <hr class="sidebar-divider">

    <div class="sidebar-heading">
      各類卡池
    </div>

    <router-link v-for="data of this.$store.getters.datas.gachaTypeList" :key="data.key" :to="{path: '/gacha/' + data.key}" v-slot="{ href, navigate, isActive }" custom>
      <li :class="['nav-item', isActive && 'active']">
        <a :class="['nav-link']" :href="href" @click="navigate">
          <i class="fas fa-star"></i>
          <span>{{ data.name }}</span>
        </a>
      </li>
    </router-link>

    <hr class="sidebar-divider">

    <div class="sidebar-heading">
      其他
    </div>

    <router-link to="/history" v-slot="{ href, navigate, isActive }" custom>
      <li :class="['nav-item', isActive && 'active']">
        <a :class="['nav-link']" :href="href" @click="navigate">
          <i class="fas fa-fw fa-table"></i>
          <span>歷史紀錄</span>
        </a>
      </li>
    </router-link>

    <hr class="sidebar-divider d-none d-md-block">

    <div class="text-center d-none d-md-inline">
      <button class="rounded-circle border-0" id="sidebarToggle"></button>
    </div>
  </ul>
</template>

<script>
export default {
  name: 'NavbarLayout',
  methods: {
    openExternal (link) {
      window.shell.openExternal(link)
    }
  },
  mounted () {
    this.$nextTick(function () {
      (function ($) {
        'use strict' // Start of use strict

        const sidebar = $('.sidebar')

        // Toggle the side navigation
        $('#sidebarToggle, #sidebarToggleTop').on('click', function (e) {
          $('body').toggleClass('sidebar-toggled')
          sidebar.toggleClass('toggled')
          if (sidebar.hasClass('toggled')) {
            $('.sidebar .collapse').collapse('hide')
          }
        })

        // Close any open menu accordions when window is resized below 768px
        $(window).resize(function () {
          if ($(window).width() < 768) {
            $('.sidebar .collapse').collapse('hide')
          }

          // Toggle the side navigation when window is resized below 480px
          if ($(window).width() < 480 && !sidebar.hasClass('toggled')) {
            $('body').addClass('sidebar-toggled')
            $('.sidebar').addClass('toggled')
            $('.sidebar .collapse').collapse('hide')
          }
        })

        // Prevent the content wrapper from scrolling when the fixed side navigation hovered over
        $('body.fixed-nav .sidebar').on('mousewheel DOMMouseScroll wheel', function (e) {
          if ($(window).width() > 768) {
            const e0 = e.originalEvent
            const delta = e0.wheelDelta || -e0.detail
            this.scrollTop += (delta < 0 ? 1 : -1) * 30
            e.preventDefault()
          }
        })

        // Scroll to top button appear
        $(document).on('scroll', function () {
          const scrollDistance = $(this).scrollTop()
          if (scrollDistance > 100) {
            $('.scroll-to-top').fadeIn()
          } else {
            $('.scroll-to-top').fadeOut()
          }
        })

        // Smooth scrolling using jQuery easing
        $(document).on('click', 'a.scroll-to-top', function (e) {
          const $anchor = $(this)
          $('html, body').stop().animate({
            scrollTop: ($($anchor.attr('href')).offset().top)
          }, 1000, 'easeInOutExpo')
          e.preventDefault()
        })
        // eslint-disable-next-line no-undef
      })(jQuery) // End of use strict
    })
  }
}
</script>
