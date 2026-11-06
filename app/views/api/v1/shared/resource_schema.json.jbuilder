# frozen_string_literal: true

# OPTIONS on a delivery resource (DeliverySchema::Resource): what it takes and
# the JSON Schema of what it answers.
json.resource @resource.resource
json.set! "methods", ["GET"]
json.params @resource.params
json.schema @resource.schema
