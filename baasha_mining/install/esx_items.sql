-- Baasha Mining items for ESX (run on your database). Images: your inventory's image folder.
INSERT IGNORE INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
  ('ore_stone', 'Stone', 1, 0, 1),
  ('ore_coal', 'Coal', 1, 0, 1),
  ('ore_copper', 'Copper Ore', 1, 0, 1),
  ('ore_iron', 'Iron Ore', 1, 0, 1),
  ('ore_silver', 'Silver Ore', 1, 0, 1),
  ('ore_gold', 'Gold Ore', 1, 0, 1),
  ('ingot_copper', 'Copper Ingot', 1, 0, 1),
  ('ingot_iron', 'Iron Ingot', 1, 0, 1),
  ('ingot_silver', 'Silver Ingot', 1, 0, 1),
  ('ingot_gold', 'Gold Ingot', 1, 0, 1),
  ('gem_amethyst', 'Amethyst', 1, 0, 1),
  ('gem_emerald', 'Emerald', 1, 0, 1),
  ('gem_sapphire', 'Sapphire', 1, 0, 1),
  ('gem_ruby', 'Ruby', 1, 0, 1),
  ('gem_diamond', 'Diamond', 1, 0, 1);
