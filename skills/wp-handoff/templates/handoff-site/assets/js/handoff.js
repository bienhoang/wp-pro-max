/* handoff.js — nav behavior for the exported handoff site.
   Classic script (no modules, no fetch) so it runs when index.html is opened
   directly from the filesystem (file://). Provides: smooth-scroll on nav click
   (honoring prefers-reduced-motion), scrollspy to highlight the active section,
   a collapsible Guides group, and a mobile nav drawer toggle. */
(function () {
  "use strict";

  var reduceMotion = window.matchMedia &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  var sidenav = document.querySelector(".sidenav");
  var navLinks = Array.prototype.slice.call(
    document.querySelectorAll('.sidenav a[href^="#"]'));
  var sections = navLinks
    .map(function (a) { return document.getElementById(a.getAttribute("href").slice(1)); })
    .filter(Boolean);

  // ---- Smooth scroll + close drawer on click ----
  navLinks.forEach(function (a) {
    a.addEventListener("click", function (e) {
      var id = a.getAttribute("href").slice(1);
      var target = document.getElementById(id);
      if (!target) return;
      e.preventDefault();
      target.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "start" });
      history.replaceState(null, "", "#" + id);
      document.body.classList.remove("nav-open");
      setActive(a);
    });
  });

  function setActive(activeLink) {
    navLinks.forEach(function (a) { a.classList.remove("is-active"); });
    if (activeLink) activeLink.classList.add("is-active");
  }

  // ---- Scrollspy ----
  if ("IntersectionObserver" in window && sections.length) {
    var visible = {};
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        visible[entry.target.id] = entry.isIntersecting ? entry.intersectionRatio : 0;
      });
      var bestId = null, best = 0;
      Object.keys(visible).forEach(function (id) {
        if (visible[id] > best) { best = visible[id]; bestId = id; }
      });
      if (bestId) {
        var link = navLinks.filter(function (a) {
          return a.getAttribute("href") === "#" + bestId;
        })[0];
        if (link) setActive(link);
      }
    }, { rootMargin: "-10% 0px -70% 0px", threshold: [0, 0.25, 0.5, 1] });
    sections.forEach(function (s) { observer.observe(s); });
  }

  // ---- Collapsible groups (Guides) ----
  Array.prototype.slice.call(document.querySelectorAll(".nav-group__toggle"))
    .forEach(function (btn) {
      btn.addEventListener("click", function () {
        var group = btn.closest(".nav-group");
        var collapsed = group.classList.toggle("is-collapsed");
        btn.setAttribute("aria-expanded", String(!collapsed));
      });
    });

  // ---- Mobile drawer ----
  var toggle = document.getElementById("nav-toggle");
  if (toggle) {
    toggle.addEventListener("click", function () {
      var open = document.body.classList.toggle("nav-open");
      toggle.setAttribute("aria-expanded", String(open));
    });
  }
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") document.body.classList.remove("nav-open");
  });
})();
