"use client";

import { useEffect, useRef, useState } from "react";

type WheelPickerProps = {
  value: number;
  onChange: (value: number) => void;
  min?: number;
  max?: number;
  step?: number;
  label?: string;
};

export function WheelPicker({
  value,
  onChange,
  min = 0,
  max = 200,
  step = 1,
  label,
}: WheelPickerProps) {
  const [isDragging, setIsDragging] = useState(false);
  const [startY, setStartY] = useState(0);
  const [scrollOffset, setScrollOffset] = useState(0);
  const containerRef = useRef<HTMLDivElement>(null);
  const itemHeight = 32; // Height of each item in pixels

  // Generate list of values
  const values: number[] = [];
  for (let i = min; i <= max; i += step) {
    values.push(i);
  }

  const currentIndex = values.indexOf(value);
  const validIndex = currentIndex === -1 ? 0 : currentIndex;

  // Calculate visible range (show 1 item above and below)
  const visibleCount = 3;
  const halfVisible = Math.floor(visibleCount / 2);

  const getVisibleValues = (): (number | null)[] => {
    const start = Math.max(0, validIndex - halfVisible);
    const end = Math.min(values.length, validIndex + halfVisible + 1);
    const visible: (number | null)[] = values.slice(start, end);

    // Pad with empty slots if needed
    while (visible.length < visibleCount) {
      if (start === 0) {
        visible.push(null);
      } else {
        visible.unshift(null);
      }
    }

    return visible;
  };

  const handleTouchStart = (e: React.TouchEvent) => {
    setIsDragging(true);
    setStartY(e.touches[0].clientY);
    setScrollOffset(0);
  };

  const handleTouchMove = (e: React.TouchEvent) => {
    if (!isDragging) return;

    const currentY = e.touches[0].clientY;
    const delta = currentY - startY;
    setScrollOffset(delta);
  };

  const handleTouchEnd = () => {
    if (!isDragging) return;

    setIsDragging(false);

    // Calculate how many steps to move based on scroll offset
    const steps = Math.round(scrollOffset / itemHeight);
    const newIndex = Math.max(0, Math.min(values.length - 1, validIndex - steps));

    if (newIndex !== validIndex) {
      onChange(values[newIndex]);
    }

    setScrollOffset(0);
    setStartY(0);
  };

  const handleMouseDown = (e: React.MouseEvent) => {
    setIsDragging(true);
    setStartY(e.clientY);
    setScrollOffset(0);
  };

  const handleMouseMove = (e: MouseEvent) => {
    if (!isDragging) return;

    const delta = e.clientY - startY;
    setScrollOffset(delta);
  };

  const handleMouseUp = () => {
    if (!isDragging) return;

    setIsDragging(false);

    const steps = Math.round(scrollOffset / itemHeight);
    const newIndex = Math.max(0, Math.min(values.length - 1, validIndex - steps));

    if (newIndex !== validIndex) {
      onChange(values[newIndex]);
    }

    setScrollOffset(0);
    setStartY(0);
  };

  useEffect(() => {
    if (!isDragging) return;

    window.addEventListener("mousemove", handleMouseMove);
    window.addEventListener("mouseup", handleMouseUp);

    return () => {
      window.removeEventListener("mousemove", handleMouseMove);
      window.removeEventListener("mouseup", handleMouseUp);
    };
  }, [isDragging, startY, validIndex]);

  const handleIncrement = () => {
    const newIndex = Math.min(values.length - 1, validIndex + 1);
    if (newIndex !== validIndex) {
      onChange(values[newIndex]);
    }
  };

  const handleDecrement = () => {
    const newIndex = Math.max(0, validIndex - 1);
    if (newIndex !== validIndex) {
      onChange(values[newIndex]);
    }
  };

  const visibleValues = getVisibleValues();
  const centerIndex = Math.floor(visibleCount / 2);

  return (
    <div className="relative flex flex-col items-center">
      {label && (
        <div className="text-xs text-muted-foreground mb-1">{label}</div>
      )}

      <div className="relative w-full">
        {/* Increment button */}
        <button
          type="button"
          onClick={handleDecrement}
          className="absolute top-0 left-0 right-0 h-8 flex items-center justify-center text-muted-foreground hover:text-foreground z-10"
          disabled={validIndex === 0}
        >
          <svg
            width="12"
            height="12"
            viewBox="0 0 16 16"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
            className="opacity-50"
          >
            <path
              d="M4 10L8 6L12 10"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </button>

        {/* Wheel container */}
        <div
          ref={containerRef}
          className="relative h-24 overflow-hidden select-none cursor-grab active:cursor-grabbing"
          onTouchStart={handleTouchStart}
          onTouchMove={handleTouchMove}
          onTouchEnd={handleTouchEnd}
          onMouseDown={handleMouseDown}
        >
          {/* Selection indicator */}
          <div className="absolute left-0 right-0 top-1/2 -translate-y-1/2 h-8 border-y-2 border-primary/20 bg-primary/5 pointer-events-none z-10" />

          {/* Values */}
          <div
            className="relative transition-transform"
            style={{
              transform: `translateY(calc(50% - ${itemHeight / 2}px + ${scrollOffset}px))`,
              transitionDuration: isDragging ? "0ms" : "200ms",
            }}
          >
            {visibleValues.map((val, idx) => {
              const isCenter = idx === centerIndex;
              const distance = Math.abs(idx - centerIndex);
              const opacity = Math.max(0.2, 1 - distance * 0.3);
              const scale = Math.max(0.7, 1 - distance * 0.15);

              return (
                <div
                  key={idx}
                  className="flex items-center justify-center transition-all"
                  style={{
                    height: `${itemHeight}px`,
                    opacity,
                    transform: `scale(${scale})`,
                  }}
                >
                  <span
                    className={`text-lg font-bold transition-colors ${
                      isCenter
                        ? "text-foreground"
                        : "text-muted-foreground"
                    }`}
                  >
                    {val !== null ? val : ""}
                  </span>
                </div>
              );
            })}
          </div>
        </div>

        {/* Decrement button */}
        <button
          type="button"
          onClick={handleIncrement}
          className="absolute bottom-0 left-0 right-0 h-8 flex items-center justify-center text-muted-foreground hover:text-foreground z-10"
          disabled={validIndex === values.length - 1}
        >
          <svg
            width="12"
            height="12"
            viewBox="0 0 16 16"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
            className="opacity-50"
          >
            <path
              d="M4 6L8 10L12 6"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        </button>
      </div>
    </div>
  );
}
