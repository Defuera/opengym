// Unit conversion utilities
// Weights are stored in kg in the database

export type Unit = "metric" | "imperial";

const KG_TO_LBS = 2.20462;
const LBS_TO_KG = 1 / KG_TO_LBS;

export function kgToLbs(kg: number): number {
  return kg * KG_TO_LBS;
}

export function lbsToKg(lbs: number): number {
  return lbs * LBS_TO_KG;
}

export function formatWeight(weightInKg: number, unit: Unit): string {
  if (unit === "imperial") {
    return `${Math.round(kgToLbs(weightInKg))} lbs`;
  }
  return `${weightInKg} kg`;
}

export function getUnitLabel(unit: Unit): string {
  return unit === "imperial" ? "lbs" : "kg";
}

export function convertWeightForDisplay(weightInKg: number, unit: Unit): number {
  if (unit === "imperial") {
    return Math.round(kgToLbs(weightInKg));
  }
  return weightInKg;
}

export function convertWeightForStorage(weight: number, unit: Unit): number {
  if (unit === "imperial") {
    return lbsToKg(weight);
  }
  return weight;
}

export function getWeightIncrement(unit: Unit): number {
  return unit === "imperial" ? 5 : 2.5;
}
