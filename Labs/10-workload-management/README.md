# Workload management
- Running mixed workloads can pose resource challenges on busy systems.

## Concepts
### Workload classification
 - The concept of assigning a request to a workload group and setting importance levels.
 - Provides a richer set of options such as label, session, and time to classify requests.

### Workload importance
 - Influences the order in which a request gets access to resources. On a busy system, a request with higher importance has first access to resources
 - Importance can also ensure ordered access to locks.

### Workload isolation
 - Reserves resources for a workload group
 - Resources reserved in a workload group are held exclusively for that workload group to ensure execution
 - Workload groups also allow you to define the amount of resources that are assigned per request, much like resource classes do
 - Workload groups give you the ability to reserve or cap the amount of resources a set of requests can consume. 
 - Finally, workload groups are a mechanism to apply rules, such as query timeout, to requests.

## Workload classification
