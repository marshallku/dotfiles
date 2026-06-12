// deck-core.js — navigation engine + plugin layer for single-file HTML decks.
// Inlined verbatim into every generated deck. Interactions never modify this file;
// they register through deck.use({ name, init, onSlideChange, onStepReveal }).
(() => {
    "use strict";

    const STAGE_WIDTH = 1920;
    const STAGE_HEIGHT = 1080;
    const SWIPE_THRESHOLD_PX = 60;

    const stage = document.querySelector(".deck-stage");
    const slides = [...document.querySelectorAll(".slide")];

    if (!stage || slides.length === 0) {
        console.error("deck-core: .deck-stage with .slide children is required");
        return;
    }

    const plugins = [];
    let currentIndex = 0;

    const getSteps = (slide) => [...slide.querySelectorAll("[data-step]")];

    const invokeHook = (plugin, hook, payload) => {
        try {
            plugin[hook]?.(payload);
        } catch (error) {
            console.error(`deck-core: plugin "${plugin.name}" failed on ${hook}:`, error);
        }
    };

    const emit = (hook, payload) => {
        plugins.forEach((plugin) => invokeHook(plugin, hook, payload));
    };

    const updateProgress = () => {
        const bar = document.querySelector(".deck-progress-bar");

        if (!bar) return;

        bar.style.width = `${((currentIndex + 1) / slides.length) * 100}%`;
    };

    const setStepsRevealed = (slide, revealed) => {
        getSteps(slide).forEach((el) => el.classList.toggle("revealed", revealed));
    };

    const goTo = (index) => {
        if (index < 0 || index >= slides.length || index === currentIndex) return;

        // Backward navigation lands with every step revealed; forward starts fresh.
        const movingBackwards = index < currentIndex;

        slides[currentIndex].classList.remove("active");
        slides[index].classList.add("active");
        setStepsRevealed(slides[index], movingBackwards);
        currentIndex = index;
        history.replaceState(null, "", `#${index + 1}`);
        updateProgress();
        emit("onSlideChange", { deck, slide: slides[index], index });
    };

    const next = () => {
        const pending = getSteps(slides[currentIndex]).find((el) => !el.classList.contains("revealed"));

        if (pending) {
            pending.classList.add("revealed");
            emit("onStepReveal", { deck, element: pending, index: currentIndex });
            return;
        }

        goTo(currentIndex + 1);
    };

    const prev = () => {
        const revealed = getSteps(slides[currentIndex]).filter((el) => el.classList.contains("revealed"));

        if (revealed.length > 0) {
            revealed[revealed.length - 1].classList.remove("revealed");
            return;
        }

        goTo(currentIndex - 1);
    };

    const deck = {
        get index() {
            return currentIndex;
        },
        slides,
        stage,
        goTo,
        next,
        prev,
        use(plugin) {
            plugins.push(plugin);
            invokeHook(plugin, "init", { deck });
            // Plugins register after start() in the generated file, so replay the current
            // slide to keep the "onSlideChange includes the start slide" contract.
            invokeHook(plugin, "onSlideChange", { deck, slide: slides[currentIndex], index: currentIndex });
            return deck;
        },
    };

    const scaleStage = () => {
        const scale = Math.min(window.innerWidth / STAGE_WIDTH, window.innerHeight / STAGE_HEIGHT);
        const offsetX = (window.innerWidth - STAGE_WIDTH * scale) / 2;
        const offsetY = (window.innerHeight - STAGE_HEIGHT * scale) / 2;

        stage.style.transform = `translate(${offsetX}px, ${offsetY}px) scale(${scale})`;
    };

    const handleKeydown = (event) => {
        const keyActions = {
            ArrowRight: next,
            ArrowDown: next,
            PageDown: next,
            " ": next,
            ArrowLeft: prev,
            ArrowUp: prev,
            PageUp: prev,
            Home: () => goTo(0),
            End: () => goTo(slides.length - 1),
        };
        const action = keyActions[event.key];

        if (!action) return;
        if (event.target instanceof HTMLElement && event.target.isContentEditable) return;

        event.preventDefault();
        action();
    };

    let touchStartX = 0;

    const handleTouchStart = (event) => {
        touchStartX = event.changedTouches[0].clientX;
    };

    const handleTouchEnd = (event) => {
        const deltaX = event.changedTouches[0].clientX - touchStartX;

        if (Math.abs(deltaX) < SWIPE_THRESHOLD_PX) return;

        if (deltaX < 0) {
            next();
        } else {
            prev();
        }
    };

    const start = () => {
        const fromHash = Number.parseInt(window.location.hash.slice(1), 10);
        const initialIndex = Number.isInteger(fromHash)
            ? Math.min(Math.max(fromHash - 1, 0), slides.length - 1)
            : 0;

        currentIndex = initialIndex;
        slides[initialIndex].classList.add("active");
        scaleStage();
        updateProgress();
        emit("onSlideChange", { deck, slide: slides[initialIndex], index: initialIndex });
    };

    window.addEventListener("resize", scaleStage, { passive: true });
    document.addEventListener("keydown", handleKeydown);
    document.addEventListener("touchstart", handleTouchStart, { passive: true });
    document.addEventListener("touchend", handleTouchEnd, { passive: true });

    window.deck = deck;
    start();
})();
