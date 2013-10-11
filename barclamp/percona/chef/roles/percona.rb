name "percona"
description "Percona Role"
run_list(
        "recipe[percona::client]",
        "recipe[percona::cluster]",
        "recipe[percona::monitoring]"
)
default_attributes()
override_attributes()
