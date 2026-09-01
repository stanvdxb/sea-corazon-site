/* SHIP MANAGEMENT clone — interactions */
(function () {
  'use strict';

  /* mobile nav */
  var toggle = document.getElementById('nav-toggle');
  var nav = document.getElementById('main-nav');
  if (toggle && nav) {
    toggle.addEventListener('click', function () {
      var open = nav.classList.toggle('open');
      toggle.setAttribute('aria-expanded', String(open));
      toggle.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
    });
    nav.addEventListener('click', function (e) {
      if (e.target.tagName === 'A') {
        nav.classList.remove('open');
        toggle.setAttribute('aria-expanded', 'false');
      }
    });
  }

  /* testimonial slider */
  var quotes = Array.prototype.slice.call(document.querySelectorAll('.quote'));
  var dots = Array.prototype.slice.call(document.querySelectorAll('.quote-dots button'));
  var slide = 0, timer = null;
  function show(i) {
    slide = (i + quotes.length) % quotes.length;
    quotes.forEach(function (q, k) { q.classList.toggle('is-active', k === slide); });
    dots.forEach(function (d, k) { d.setAttribute('aria-selected', String(k === slide)); });
  }
  function autoplay() {
    if (timer) clearInterval(timer);
    if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      timer = setInterval(function () { show(slide + 1); }, 6000);
    }
  }
  dots.forEach(function (d) {
    d.addEventListener('click', function () { show(parseInt(d.dataset.slide, 10)); autoplay(); });
  });
  autoplay();

  /* scroll-to-top */
  var top = document.getElementById('to-top');
  if (top) {
    window.addEventListener('scroll', function () {
      top.classList.toggle('show', window.scrollY > 500);
    }, { passive: true });
    top.addEventListener('click', function () {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });
  }

  /* fake form handlers (static clone — no backend) */
  function wireForm(id, noteId) {
    var f = document.getElementById(id), note = document.getElementById(noteId);
    if (!f || !note) return;
    f.addEventListener('submit', function (e) {
      e.preventDefault();
      if (!f.checkValidity()) {
        note.textContent = 'Please fill in all required fields.';
        note.style.color = '#ffd9d9';
        f.reportValidity();
        return;
      }
      note.textContent = 'Thank you! This is a static clone — no request was sent.';
      note.style.color = '';
      f.reset();
    });
  }
  wireForm('callback-form', 'cb-note');
  wireForm('contact-form', 'ct-note');

  /* reveal on scroll */
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var targets = document.querySelectorAll('.card, .priority, .feature-block, .about .lead, .priorities-head > div');
  if (!reduce && 'IntersectionObserver' in window) {
    targets.forEach(function (el) { el.classList.add('reveal'); });
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add('in'); io.unobserve(en.target); }
      });
    }, { threshold: 0.12 });
    targets.forEach(function (el) { io.observe(el); });
  }
})();
