/* Sea Corazon Ship Management — clone behaviour.
   No dependencies. The original ran jQuery + Elementor + ElementsKit for this. */
(function () {
  'use strict';

  /* ---- scroll reveal ----------------------------------------------------
     The head script adds .js-reveal before first paint only when an observer
     exists and the visitor has not asked for reduced motion; this is the
     matching half. Elements never depend on it to be visible. */
  window.__revealReady = true;
  var revealEls = document.querySelectorAll('.reveal');
  if (revealEls.length && document.documentElement.classList.contains('js-reveal')) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        var el = entry.target, i = 0, sib = el;
        while ((sib = sib.previousElementSibling) && i < 4) { if (sib.classList.contains('reveal')) i++; }
        el.style.transitionDelay = (i * 70) + 'ms';   // small groups only: cards in a row
        el.classList.add('is-in');
        io.unobserve(el);
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -8% 0px' });
    revealEls.forEach(function (el) { io.observe(el); });
  } else {
    document.documentElement.classList.remove('js-reveal');
  }

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
     Posts to /api/contact (deploy/contact-api on the server). Validation here
     mirrors the server's; the status line under the button is aria-live so
     screen readers hear the outcome. If the API is unreachable the visitor is
     told how to reach us instead of being left guessing. */
  var FALLBACK = 'We couldn\u2019t send your message. Please call +971 4 572 3303 or email ops@corazon-tech.com.';
  document.querySelectorAll('form[data-contact-form]').forEach(function (form) {
    var status = form.querySelector('.form-status');
    var button = form.querySelector('button[type=submit]');
    var say = function (text, isError) {
      if (!status) return;
      status.textContent = text;
      status.classList.toggle('form-status--error', !!isError);
      status.classList.toggle('form-status--ok', !isError && !!text);
    };
    var invalid = function (field, text) {
      form.querySelectorAll('[aria-invalid]').forEach(function (f) { f.removeAttribute('aria-invalid'); });
      if (field) { field.setAttribute('aria-invalid', 'true'); field.focus(); }
      say(text, true);
    };
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var f = form.elements;
      var name = (f.name && f.name.value || '').trim();
      var phone = (f.phone && f.phone.value || '').trim();
      var email = (f.email && f.email.value || '').trim();
      if (name.length < 2) return invalid(f.name, 'Please enter your name.');
      if (!phone && !email) return invalid(f.phone || f.email, 'Please give a phone number or an email address.');
      if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(email)) return invalid(f.email, 'That email address doesn\u2019t look right.');
      if (phone && !/^\+?[\d\s().-]{6,24}$/.test(phone)) return invalid(f.phone, 'That phone number doesn\u2019t look right.');
      if (f.message && f.message.value.length > 4000) return invalid(f.message, 'Please shorten your message to 4000 characters or fewer.');
      if (f.consent && !f.consent.checked) return invalid(f.consent, 'Please agree to the terms and conditions.');
      form.querySelectorAll('[aria-invalid]').forEach(function (x) { x.removeAttribute('aria-invalid'); });

      var payload = {
        name: name, phone: phone, email: email,
        message: (f.message && f.message.value || '').trim(),
        consent: f.consent ? f.consent.checked : true,
        website: (f.website && f.website.value) || '',
        form: form.getAttribute('data-form-name') || '',
        page: location.pathname
      };
      button.disabled = true; say('Sending\u2026', false);
      fetch(form.getAttribute('action') || '/api/contact', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
      }).then(function (r) { return r.json().catch(function () { return { ok: r.ok }; }).then(function (d) { return { http: r.status, d: d }; }); })
        .then(function (res) {
          if (res.d && res.d.ok) { form.reset(); say('Thank you \u2014 we have your message and will contact you shortly.', false); }
          else if (res.http === 422 && res.d && res.d.error) { say(res.d.error, true); }
          else if (res.http === 429) { say('Too many messages in a short time. Please try again in a few minutes.', true); }
          else { say(FALLBACK, true); }
        })
        .catch(function () { say(FALLBACK, true); })
        .then(function () { button.disabled = false; });
    });
  });
})();
