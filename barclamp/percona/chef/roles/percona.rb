name "percona"
description "Percona Role"
run_list(
        "recipe[percona::cluster]"
)
default_attributes()
override_attributes()
