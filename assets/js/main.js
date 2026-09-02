/* Sea Corazon Ship Management — clone behaviour.
   No dependencies. The original ran jQuery + Elementor + ElementsKit for this. */
(function () {
  'use strict';

  /* ---- mobile navigation ------------------------------------------------ */
  var toggle = document.querySelector('.nav__toggle');
  var list = document.querySelector('.nav__list');

  if (toggle && list) {
    toggle.addEventListener('click', function () {
      var open = toggle.getAttribute('aria-expanded') === 'true';
      toggle.setAttribute('aria-expanded', String(!open));
      list.classList.toggle('is-open', !open);
    });
  }

  /* Submenus open on hover at desktop widths; on touch/narrow widths the
     parent link toggles instead of navigating. */
  document.querySelectorAll('.nav__item--has-children > .nav__link').forEach(function (link) {
    link.addEventListener('click', function (e) {
      if (window.matchMedia('(max-width: 1024px)').matches) {
        e.preventDefault();
        link.parentNode.classList.toggle('is-open');
      }
    });
  });

  document.addEventListener('click', function (e) {
    if (!list || !list.classList.contains('is-open')) return;
    if (e.target.closest('.masthead__inner')) return;
    list.classList.remove('is-open');
    if (toggle) toggle.setAttribute('aria-expanded', 'false');
  });

  /* ---- accordions ------------------------------------------------------- */
  document.querySelectorAll('.accordion').forEach(function (accordion) {
    var single = accordion.dataset.single !== 'false';
    accordion.querySelectorAll('.accordion__trigger').forEach(function (trigger) {
      trigger.addEventListener('click', function () {
        var item = trigger.closest('.accordion__item');
        var open = item.getAttribute('data-open') === 'true';
        if (single) {
          accordion.querySelectorAll('.accordion__item').forEach(function (other) {
            other.setAttribute('data-open', 'false');
            other.querySelector('.accordion__trigger').setAttribute('aria-expanded', 'false');
          });
        }
        item.setAttribute('data-open', String(!open));
        trigger.setAttribute('aria-expanded', String(!open));
      });
    });
  });

  /* ---- carousels --------------------------------------------------------
     The source runs Swiper. This gives the same result with scroll-snap:
     the track is scrollable and keyboard-reachable on its own, and the dots
     drive it. With JS off you still get a horizontally scrollable strip. */
  document.querySelectorAll('.carousel').forEach(function (carousel) {
    var track = carousel.querySelector('.carousel__track');
    var slides = [].slice.call(carousel.querySelectorAll('.carousel__slide'));
    var dots = [].slice.call(carousel.querySelectorAll('.carousel__dot'));
    if (!track || slides.length < 2) return;

    var goTo = function (i) {
      track.scrollTo({ left: slides[i].offsetLeft - track.offsetLeft, behavior: 'smooth' });
    };

    dots.forEach(function (dot, i) {
      dot.addEventListener('click', function () { goTo(i); });
    });

    var sync = function () {
      var mid = track.scrollLeft + track.clientWidth / 2;
      var active = 0;
      slides.forEach(function (slide, i) {
        var left = slide.offsetLeft - track.offsetLeft;
        if (left <= mid) active = i;
      });
      dots.forEach(function (dot, i) {
        dot.setAttribute('aria-selected', String(i === active));
      });
    };

    var frame;
    track.addEventListener('scroll', function () {
      if (frame) cancelAnimationFrame(frame);
      frame = requestAnimationFrame(sync);
    }, { passive: true });
    sync();
  });

  /* ---- tabs -------------------------------------------------------------- */
  document.querySelectorAll('.tabs').forEach(function (tabs) {
    var buttons = [].slice.call(tabs.querySelectorAll('.tabs__tab'));
    var panels = [].slice.call(tabs.querySelectorAll('.tabs__panel'));
    if (!buttons.length) return;

    var select = function (index) {
      buttons.forEach(function (b, i) {
        b.setAttribute('aria-selected', String(i === index));
        b.setAttribute('tabindex', i === index ? '0' : '-1');
      });
      panels.forEach(function (panel, i) { panel.hidden = i !== index; });
    };

    buttons.forEach(function (button, i) {
      button.addEventListener('click', function () { select(i); });
      button.addEventListener('keydown', function (e) {
        var next = e.key === 'ArrowRight' ? i + 1 : e.key === 'ArrowLeft' ? i - 1 : null;
        if (next === null) return;
        e.preventDefault();
        next = (next + buttons.length) % buttons.length;
        buttons[next].focus();
        select(next);
      });
    });

    var initial = buttons.findIndex(function (b) { return b.getAttribute('aria-selected') === 'true'; });
    select(initial < 0 ? 0 : initial);
  });

  /* ---- theme toggle ------------------------------------------------------
     The stylesheet already follows the system preference. The button lets a
     visitor override it; the choice is remembered and applied before first
     paint by the inline script in <head>. */
  var themeBtn = document.querySelector('.theme-toggle');
  if (themeBtn) {
    var root = document.documentElement;
    var systemDark = window.matchMedia('(prefers-color-scheme: dark)');
    var isDark = function () {
      var t = root.getAttribute('data-theme');
      return t ? t === 'dark' : systemDark.matches;
    };
    var reflect = function () {
      var dark = isDark();
      themeBtn.setAttribute('aria-pressed', String(dark));
      themeBtn.setAttribute('aria-label', dark ? 'Switch to light theme' : 'Switch to dark theme');
    };
    themeBtn.addEventListener('click', function () {
      var next = isDark() ? 'light' : 'dark';
      root.setAttribute('data-theme', next);
      try { localStorage.setItem('theme', next); } catch (e) {}
      reflect();
    });
    systemDark.addEventListener('change', reflect);
    reflect();
  }

  /* ---- scroll to top ---------------------------------------------------- */
  var toTop = document.querySelector('.to-top');
  if (toTop) {
    var sync = function () { toTop.classList.toggle('is-visible', window.scrollY > 400); };
    window.addEventListener('scroll', sync, { passive: true });
    sync();
    toTop.addEventListener('click', function () {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });
  }

  /* ---- forms ------------------------------------------------------------
     The original posts to WordPress via Metform + reCAPTCHA. This clone has no
     backend, so submissions are intercepted and acknowledged in place rather
     than failing silently against a dead endpoint. */
  document.querySelectorAll('form[data-clone-form]').forEach(function (form) {
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var status = form.querySelector('.form-status');
      if (status) {
        status.textContent = 'This is a static clone — the form is not connected to a backend.';
      }
    });
  });
})();
