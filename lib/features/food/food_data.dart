import 'dart:math';

/// Per typical single serving. Values are approximate (ICMR/IFCT + USDA averages).
class Dish {
  final String name, cuisine, diet; // diet: veg | egg | nonveg
  final Set<String> meals; // b=breakfast l=lunch s=snack d=dinner
  final int kcal;
  final double protein, carbs, fat, fiber;
  const Dish(this.name, this.cuisine, this.diet, this.meals, this.kcal, this.protein, this.carbs, this.fat, this.fiber);

  /// 0-10: rewards protein density & fibre, penalises fat-heavy dishes.
  double get healthScore {
    final pd = protein * 4 / kcal; // share of calories from protein
    final fd = fat * 9 / kcal;
    final s = 3 + pd * 10 + min(fiber * 0.3, 2.5) - (fd > 0.35 ? (fd - 0.35) * 14 : 0) - (kcal > 750 ? 1.5 : 0);
    return s.clamp(0, 10).toDouble();
  }

  static Dish? byName(String n) {
    for (final d in dishes) {
      if (d.name == n) return d;
    }
    return null;
  }
}

const cuisines = ['Any', 'North Indian', 'South Indian', 'Chinese', 'Continental', 'Fast food', 'Healthy'];

const dishes = <Dish>[
  // Breakfast
  Dish('Poha', 'North Indian', 'veg', {'b', 's'}, 270, 5, 45, 8, 3),
  Dish('Upma', 'South Indian', 'veg', {'b'}, 250, 6, 38, 8, 3),
  Dish('Idli sambar (3)', 'South Indian', 'veg', {'b', 'd'}, 300, 11, 55, 4, 6),
  Dish('Masala dosa', 'South Indian', 'veg', {'b', 'l', 'd'}, 420, 9, 58, 17, 5),
  Dish('Moong dal chilla (2)', 'Healthy', 'veg', {'b', 'd'}, 280, 16, 34, 8, 7),
  Dish('Besan chilla (2)', 'North Indian', 'veg', {'b'}, 300, 14, 32, 12, 6),
  Dish('Aloo paratha + curd', 'North Indian', 'veg', {'b', 'l'}, 480, 12, 62, 20, 5),
  Dish('Paneer paratha + curd', 'North Indian', 'veg', {'b', 'l'}, 520, 21, 55, 23, 5),
  Dish('Oats with milk & banana', 'Healthy', 'veg', {'b'}, 330, 13, 55, 7, 6),
  Dish('Greek yogurt + fruit + nuts', 'Healthy', 'veg', {'b', 's'}, 300, 18, 30, 12, 4),
  Dish('Masala omelette (3 eggs) + toast', 'Continental', 'egg', {'b', 'd'}, 420, 25, 26, 24, 2),
  Dish('Egg bhurji + 2 roti', 'North Indian', 'egg', {'b', 'l', 'd'}, 450, 23, 42, 20, 5),
  Dish('Boiled eggs (3)', 'Healthy', 'egg', {'b', 's'}, 210, 18, 2, 15, 0),
  Dish('Peanut butter toast + milk', 'Continental', 'veg', {'b', 's'}, 420, 18, 42, 20, 4),
  // Lunch / dinner — veg
  Dish('Dal tadka + rice', 'North Indian', 'veg', {'l', 'd'}, 480, 16, 78, 10, 8),
  Dish('Rajma chawal', 'North Indian', 'veg', {'l'}, 520, 18, 85, 10, 13),
  Dish('Chole + 2 roti', 'North Indian', 'veg', {'l', 'd'}, 520, 18, 75, 15, 14),
  Dish('Paneer tikka', 'North Indian', 'veg', {'s', 'd'}, 340, 22, 10, 23, 2),
  Dish('Paneer butter masala + 2 roti', 'North Indian', 'veg', {'l', 'd'}, 680, 22, 60, 38, 6),
  Dish('Palak paneer + 2 roti', 'North Indian', 'veg', {'l', 'd'}, 520, 22, 50, 25, 8),
  Dish('Veg thali', 'North Indian', 'veg', {'l'}, 750, 22, 110, 24, 14),
  Dish('Curd rice', 'South Indian', 'veg', {'l', 'd'}, 330, 9, 52, 9, 2),
  Dish('Sambar rice', 'South Indian', 'veg', {'l'}, 420, 12, 72, 9, 9),
  Dish('Veg biryani + raita', 'North Indian', 'veg', {'l', 'd'}, 560, 13, 85, 18, 6),
  Dish('Soya chunk curry + rice', 'Healthy', 'veg', {'l', 'd'}, 480, 28, 65, 10, 10),
  Dish('Tofu / paneer salad bowl', 'Healthy', 'veg', {'l', 'd'}, 380, 24, 25, 20, 9),
  Dish('Quinoa veg bowl', 'Healthy', 'veg', {'l', 'd'}, 420, 15, 60, 13, 9),
  Dish('Khichdi + curd', 'North Indian', 'veg', {'l', 'd'}, 400, 15, 65, 9, 7),
  Dish('Veg hakka noodles', 'Chinese', 'veg', {'l', 'd'}, 520, 11, 75, 19, 5),
  Dish('Veg fried rice + manchurian', 'Chinese', 'veg', {'l', 'd'}, 720, 14, 100, 28, 6),
  Dish('Margherita pizza (2 slices)', 'Fast food', 'veg', {'l', 'd', 's'}, 540, 22, 64, 20, 3),
  Dish('Veg burger + fries', 'Fast food', 'veg', {'l', 's'}, 760, 16, 98, 34, 7),
  Dish('Pav bhaji', 'Fast food', 'veg', {'l', 's', 'd'}, 600, 13, 80, 25, 9),
  Dish('Pasta arrabbiata', 'Continental', 'veg', {'l', 'd'}, 520, 16, 85, 13, 6),
  // Lunch / dinner — non-veg
  Dish('Grilled chicken + veggies', 'Healthy', 'nonveg', {'l', 'd'}, 420, 45, 15, 18, 5),
  Dish('Tandoori chicken (half)', 'North Indian', 'nonveg', {'l', 'd'}, 450, 55, 6, 22, 1),
  Dish('Chicken curry + rice', 'North Indian', 'nonveg', {'l', 'd'}, 650, 35, 75, 22, 4),
  Dish('Butter chicken + naan', 'North Indian', 'nonveg', {'l', 'd'}, 900, 40, 70, 48, 4),
  Dish('Chicken biryani + raita', 'North Indian', 'nonveg', {'l', 'd'}, 720, 35, 85, 25, 3),
  Dish('Chicken tikka', 'North Indian', 'nonveg', {'s', 'd'}, 320, 40, 6, 14, 1),
  Dish('Fish curry + rice', 'South Indian', 'nonveg', {'l', 'd'}, 560, 32, 70, 15, 3),
  Dish('Grilled fish + salad', 'Healthy', 'nonveg', {'l', 'd'}, 360, 38, 12, 16, 5),
  Dish('Egg curry + rice', 'North Indian', 'egg', {'l', 'd'}, 560, 22, 70, 20, 4),
  Dish('Chicken shawarma roll', 'Fast food', 'nonveg', {'l', 's', 'd'}, 520, 30, 50, 22, 3),
  Dish('Chicken fried rice', 'Chinese', 'nonveg', {'l', 'd'}, 620, 28, 80, 20, 3),
  Dish('Chilli chicken (dry)', 'Chinese', 'nonveg', {'s', 'd'}, 420, 30, 20, 24, 2),
  Dish('Chicken burger', 'Fast food', 'nonveg', {'l', 's'}, 520, 28, 45, 25, 2),
  Dish('Chicken salad bowl', 'Healthy', 'nonveg', {'l', 'd'}, 400, 38, 20, 18, 7),
  Dish('Mutton rogan josh + roti', 'North Indian', 'nonveg', {'l', 'd'}, 780, 40, 45, 48, 4),
  // Snacks
  Dish('Sprouts chaat', 'Healthy', 'veg', {'s', 'b'}, 180, 11, 28, 2, 8),
  Dish('Roasted chana (50g)', 'Healthy', 'veg', {'s'}, 190, 10, 30, 3, 8),
  Dish('Fruit bowl', 'Healthy', 'veg', {'s', 'b'}, 150, 2, 36, 1, 6),
  Dish('Protein shake + banana', 'Healthy', 'veg', {'s', 'b'}, 280, 28, 35, 4, 3),
  Dish('Samosa (2)', 'Fast food', 'veg', {'s'}, 520, 8, 55, 30, 4),
  Dish('Veg momos (8)', 'Chinese', 'veg', {'s', 'd'}, 340, 10, 55, 9, 4),
  Dish('Chicken momos (8)', 'Chinese', 'nonveg', {'s', 'd'}, 380, 22, 45, 12, 2),
  Dish('Makhana (roasted)', 'Healthy', 'veg', {'s'}, 150, 5, 25, 3, 3),
];
