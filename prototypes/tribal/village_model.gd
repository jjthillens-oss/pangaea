extends RefCounted

# Original, isolated proposed rules; quantities are prototype-only.
var lineage_id := "shore-lineage"
var worker_ids := ["scout", "forager"]
var food := 2
var materials := 0
var food_site := 4
var material_site := 3
var shelter_built := false
var rival_id := "reed-neighbors"
var rival_relation := 0
var rival_food := 3
var tasks := {}
var reserved_sites := {}

func assign(worker_id: String, site: String) -> bool:
	if not worker_ids.has(worker_id) or not ["food", "material"].has(site):
		return false
	if reserved_sites.has(site) and reserved_sites[site] != worker_id:
		return false
	if (food_site if site == "food" else material_site) <= 0:
		return false
	cancel(worker_id)
	tasks[worker_id] = site
	reserved_sites[site] = worker_id
	return true

func cancel(worker_id: String) -> void:
	if not tasks.has(worker_id):
		return
	var site: String = tasks[worker_id]
	tasks.erase(worker_id)
	if reserved_sites.get(site, "") == worker_id:
		reserved_sites.erase(site)

func gather(worker_id: String) -> bool:
	if not tasks.has(worker_id):
		return false
	var site: String = tasks[worker_id]
	if site == "food" and food_site > 0:
		food_site -= 1
		food += 1
	elif site == "material" and material_site > 0:
		material_site -= 1
		materials += 1
	else:
		cancel(worker_id)
		return false
	cancel(worker_id)
	return true

func build_shelter() -> bool:
	if shelter_built or materials < 2:
		return false
	materials -= 2
	shelter_built = true
	return true

func trade_food() -> bool:
	# An explicit, conserved exchange with the one neighboring group.
	if materials < 1 or rival_food < 1:
		return false
	materials -= 1
	food += 1
	rival_food -= 1
	rival_relation += 1
	return true

func warn_neighbor() -> void:
	rival_relation -= 1

func regenerate() -> void:
	food_site = mini(food_site + 1, 4)
	material_site = mini(material_site + 1, 3)
