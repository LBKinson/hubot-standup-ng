# Agile standup bot ala tender
#
# standup? - show help for standup

module.exports = (robot) ->
  robot.respond /(?:cancel|stop) standup *$/i, (msg) ->
    if !msg.message.user.room?
      msg.send "I keep track of standups by room. I can't cancel a standup if you don't tell me from a particular room."
    else if robot.brain.data.standup?[msg.message.user.room]
      delete robot.brain.data.standup?[msg.message.user.room]
      msg.send "Standup cancelled for #{msg.message.user.room}"
    else
      msg.send "I'm not aware of a standup in progress in #{msg.message.user.room}."

  robot.respond /delete standup for (.*) *$/i, (msg) ->
    if !msg.message.user.room?
      msg.send "I keep track of standups by room. I can't delete a standup if you don't tell me from a particular room."
    if robot.brain.data.standup?[msg.message.user.room]
      # remove the standup log
      delete robot.brain.data.standup?[msg.message.user.room]

      # remove any buffered email
      if robot.brain.data.tempEmailBuffer?[group]
        delete robot.brain.data.tempEmailBuffer[group]

      # remove any email setting
      if robot.brain.data.emailGroups?[group]
        delete robot.brain.data.emailGroups[group]

  robot.respond /show standup members for (.*) *$/i, (msg) ->
    room  = msg.message.user.room
    group = msg.match[1].trim()

    attendees = []
    for own key, user of robot.brain.data.users
      roles = user.roles or [ ]
      if "#{group}" in roles or "a #{group} member" in roles or "an #{group} member" in roles or "a member of #{group}" in roles
        attendees.push user
    if attendees.length > 0
      who = attendees.map((user) -> user.name).join(', ')
      msg.send "The standup members for #{group} are: #{who}"

  robot.respond /show standups *$/i, (msg) ->
    groups = []
    for own key, user of robot.brain.data.users
      roles = user.roles or [ ]
      matching_roles = roles.filter((r) -> r.match(/an? (\w+) member/) or r.match(/a member of (\w+)/))

      for r in matching_roles

        a_member = r.match(/an? (\w+) member/)
        if a_member
          role_to_add = a_member[1]

        a_member = r.match(/a member of (\w+)/)
        if a_member
          role_to_add = a_member[1]

        if role_to_add in groups
          continue

        groups.push role_to_add

    if groups.length > 0
      group_list = groups.join(', ')
      msg.send "The registered standups are: #{group_list}"

  robot.respond /standup for (\S+)\s*$/i, (msg) ->
    room  = msg.message.user.room
    group = msg.match[1].trim()
    if robot.brain.data.standup?[room]
      sendWithLog robot, msg, "The standup for #{robot.brain.data.standup[room].group} is in progress! Cancel it first with 'cancel standup'"
      return

    attendees = []
    for own key, user of robot.brain.data.users
      roles = user.roles or [ ]
      if "#{group}" in roles or "a #{group} member" in roles or "an #{group} member" in roles or "a member of #{group}" in roles
        attendees.push user
    if attendees.length > 0
      robot.brain.data.standup or= {}
      robot.brain.data.standup[room] = {
        group: group,
        start: new Date().getTime(),
        attendees: attendees,
        remaining: shuffleArrayClone(attendees)
        log: [],
      }
      who = attendees.map((user) -> user.name).join(', ')
      sendWithLog robot, msg, "Ok, let's start the standup: #{who}"
      nextPerson robot, room, msg
    else
      sendWithLog robot, msg, "Oops something's wrong, can't find anyone with 'a #{group} member' role!"

  robot.respond /(?:that\'s it|next(?: person)?|done) *$/i, (msg) ->
    unless robot.brain.data.standup?[msg.message.user.room]
      return
    if robot.brain.data.standup[msg.message.user.room].current.id isnt msg.message.user.id
      msg.reply "but it's not your turn! Use skip [someone] or next [someone] instead."
    else
      nextPerson robot, msg.message.user.room, msg

  robot.respond /(skip|next) (\S+)\s*$/i, (msg) ->
    unless robot.brain.data.standup?[msg.message.user.room]
      return

    is_skip = msg.match[1] == 'skip'
    users = robot.brain.usersForFuzzyName msg.match[2].trim()
    if users.length is 1
      skip = users[0]
      standup = robot.brain.data.standup[msg.message.user.room]
      if is_skip
        standup.remaining = (user for user in standup.remaining when user.name != skip.name)
        if standup.current.id is skip.id
          nextPerson robot, msg.message.user.room, msg
        else
          sendWithLog robot, msg, "Ok, I will skip #{skip.name}"
      else
        if standup.current.id is skip.id
          standup.remaining.push skip
          nextPerson robot, msg.message.user.room, msg
        else
          sendWithLog robot, msg, "But it is not #{skip.name}'s turn!"
    else if users.length > 1
      sendWithLog robot, msg, "Be more specific, I know #{users.length} people named like that: #{(user.name for user in users).join(", ")}"
    else
      sendWithLog robot, msg, "#{msg.match[2]}? Never heard of 'em"

  robot.respond /standup\?? *$/i, (msg) ->
    sendWithLog robot, msg, """
             <user> has <team> role - tell johnny-5 who is the member of <team>'s standup
             show standup members for <team> - list all of the members of <team>'s standup
             show standups - list of all standups defined by user roles for any room
             standup for <team> - start the standup for <team>
             delete standup for <team> - erase all record of standup for <team>
             cancel standup - cancel the current standup
             next - say when your updates for the standup is done
             skip <who> - skip someone when they're not available
             no standup emails for <team> - disable emails for that team
             email <team> standup logs to <email address> - set email destination for standup log
             """

  robot.hear /(.*)/, (msg) ->
    current_standup = robot.brain.data.standup?[msg.message.user.room]
    if msg.message.user.room? && current_standup?
      console.log "Standup log added from #{msg.message.user.name} in #{msg.message.user.room}: -#{msg.message}-"
      robot.brain.data.standup[msg.message.user.room].log.push { message: msg.message, time: new Date().getTime() }
    #else
    #  console.log "Heard message from #{msg.message.user.name} in #{msg.message.user.room} but there was no current standup there."

shuffleArrayClone = (array) ->
  cloned = []
  for i in (array.sort -> 0.5 - Math.random())
    cloned.push i
  cloned

nextPerson = (robot, room, msg) ->
  standup = robot.brain.data.standup[room]
  if standup.remaining.length == 0
    howlong = calcMinutes(new Date().getTime() - standup.start)
    body = "Standup log for (#{new Date().getDay()}): \n==================================\n"
    
    for log in standup.log
      logMessage = "#{log.message.text}"
      console.log logMessage
      console.log logMessage.constructor.name
      console.log logMessage.toString().startsWith 'johnny-5'
      if log.message.user.name == 'johnny-5' || String(logMessage).startsWith 'johnny-5'
        body += "\n"
      else
        body += "(#{new Date(log.time).toLocaleTimeString()}) <#{log.message.user.name}> #{log.message.text}\n"
      
    sendWithLog robot, msg, "All done! Standup was #{howlong}. Here's a summary: #{body}"
    try
      robot.brain.emit 'standupLog', standup.group, room, msg, standup.log
    catch
      sendWithLog robot, msg, "Standup log failed"
      console.log "standupLog event failed"
    delete robot.brain.data.standup[room]
  else
    standup.current = standup.remaining.shift()
    sendWithLog robot, msg, "#{addressUser(standup.current.name, robot.adapter)} your turn"

addressUser = (name, adapter) ->
  className = adapter.__proto__.constructor.name
  switch className
    when "HipChat" then "@#{name.replace(' ', '')}"
    else "#{name}:"

calcMinutes = (milliseconds) ->
  seconds = Math.floor(milliseconds / 1000)
  if seconds > 60
    minutes = Math.floor(seconds / 60)
    seconds = seconds % 60
    "#{minutes} minutes and #{seconds} seconds"
  else
    "#{seconds} seconds"

sendWithLog = (robot, msg, content) ->
  msg.send(content)
  fakemessage =
     user:
       name: robot.name
     text: content
  robot.brain.data.standup[msg.message.user.room].log.push { message: fakemessage, time: new Date().getTime() }
