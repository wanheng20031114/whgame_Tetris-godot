const progress = document.querySelector("#scrollProgress");
const navLinks = [...document.querySelectorAll(".toc a")];
const sections = navLinks
  .map((link) => document.querySelector(link.getAttribute("href")))
  .filter(Boolean);

function updateProgress() {
  const max = document.documentElement.scrollHeight - window.innerHeight;
  const ratio = max <= 0 ? 0 : window.scrollY / max;
  progress.style.width = `${Math.min(100, Math.max(0, ratio * 100))}%`;

  let activeId = sections[0]?.id;
  for (const section of sections) {
    const rect = section.getBoundingClientRect();
    if (rect.top <= window.innerHeight * 0.38) {
      activeId = section.id;
    }
  }

  navLinks.forEach((link) => {
    link.classList.toggle("active", link.getAttribute("href") === `#${activeId}`);
  });
}

const revealObserver = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("visible");
      }
    });
  },
  { threshold: 0.12 }
);

document.querySelectorAll(".hero-media, .principle-list div, .journey article, .feature-item, .image-pair figure, .large-shot, .replay-points article, .stats-row figure, .mode-strip article, .arch-node, .tech-stack div").forEach((el) => {
  el.classList.add("reveal");
  revealObserver.observe(el);
});

window.addEventListener("scroll", updateProgress, { passive: true });
window.addEventListener("resize", updateProgress);
updateProgress();
