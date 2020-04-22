# RabbitMQ Chef Resources
## Warning - Full Transparency
I needed this for work, so I intend to continue to work on this when needed and/or when I have time. It's still very early in development, so it's maybe a two-trick pony, at the moment. But if you need some quick Chef resources that will get a cluster up and running for you, you're (probably) in the right place! I know I've had a difficult time getting Chef to successfully manage my RabbitMQ clusters, so hopefully this helps someone in a similar situation.

## Overview
These are just some custom Chef resources for configuring and managing RabbitMQ nodes. These resources should allow you to create a cluster, join a node to a cluster, create/configure internal users, etc. Right now these resources have only been reliably tested on Ubuntu (16.04+).

I wound up needing a good way to manage RabbitMQ via Chef for my job. I first tried to use a cookbook maintained by some at RabbitMQ, but I found the code written to support the use of the 'classic' config format. I don't know many who are that fond of the 'classic' format, and RabbitMQ's own documentation states that it is deprecated beginning with RabbitMQ 3.7.0. I attempted a simple fork in the beginning, but I also discovered that the output of the RabbitMQ CLI has changed quite a bit; I presume it began with the 3.7.0 update. There was a great deal of string manipulation around the output of the RabbitMQ CLI, but it is now capable of formatting its output, such as in JSON. This massively simplified the Ruby needed to write up a quick custom resource for RabbitMQ utilizing the CLI.

Having said all of that, I cannot deny that their cookbook heavily inspired me. I'm not sure I could have gotten any of this done as easily as I did without it. You can take a look here: https://github.com/rabbitmq/chef-cookbook

# What is Included
  1. Custom Chef resources for RabbitMQ
  2. A few templates that you're welcome to tweak so you can configure RabbitMQ precisely the way you need. (TODO)
  3. Some example recipes. (TODO)
  
# Resources
## Bunny_Cluster
   This resource is designed to create a RabbitMQ cluster. RabbitMQ clusters need to handled with care, so way in which the    resource handles it is pretty straightfoward, and this is by design. It accepts a list of node names (with the 'rabbit@' included) and marks the first as the 'master' node to which all other nodes will target to join the cluster, using the RabbitMQ CLI (also known as a *manually joining a cluster*).
   Right now the resource only supports the 'join' action. I have some plans to add a 'remove' action. RabbitMQ clusters occasionally give me a headache, so I figured I'm probably not completely alone in that and someone out there will appreciate a simple explanation of *how* it's doing this.
   
## Bunny_Policy
  This resource will apply any policies and policy parameters provided. It also accepts a pattern if you need to be more specific about what your policies are applied to.
  
## Bunny_Reset
  This is a simple resource that resets RabbitMQ. I typically only use this when I need to change the Erlang Cookie when first setting up a cluster.
  
## Bunny_User
  This creates and manages internal RabbitMQ users. It also manages tags and permissions for those users across multiple virtual hosts. I have plans to add a 'remove' action, but it currently only supports 'add' and 'set_permissions' actions.
  
## Bunny_Vhost
  This creates virtual hosts. I have plans to add functionality that will also allow you to remove virtual hosts.
