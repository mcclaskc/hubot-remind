# Description:
#   Remind someone to something at a given time
#
# Commands:
#   hubot remind <user> in #s|m|h|d to <something to remind> - remind to someone something in a given time
#   hubot remind <user> to <something to remind> in #s|m|h|d - remind to someone something in a given time
#   hubot reminders|what are your reminders - Show active reminders
#   hubot forget|rm|remove|delete reminder <id> - Remove a given reminder

cronJob = require('cron').CronJob
moment = require('moment')

JOBS = {}
BRAIN_JOBS = [];

createNewJob = (robot, pattern, user, message) ->
  id = Math.floor(Math.random() * 1000000) while !id? || JOBS[id]
  registerNewJob robot, id, pattern, user, message
  id

registerNewJobFromBrain = (robot, id, pattern, user, message) ->
  registerNewJob(robot, id, pattern, user, message)

registerNewJob = (robot, id, pattern, user, message) ->
  job = new Job(id, pattern, user, message)
  job.start(robot)
  JOBS[id] = job
  BRAIN_JOBS.push({id: id, pattern: pattern, user: user, message: message})

unregisterJob = (robot, id)->
  if JOBS[id]
    JOBS[id].stop()
    delete JOBS[id]
    foundJobs = BRAIN_JOBS.filter (j) ->
      j.id == id
    if foundJobs
      BRAIN_JOBS.splice(BRAIN_JOBS.indexOf(foundJobs), 1)
    saveJobs(robot)
    return yes
  no

handleNewJob = (robot, msg, user, pattern, message) ->
  createNewJob robot, pattern, user, message
  saveJobs(robot)
  msg.send "Got it! I will remind #{user.name} at #{pattern}"


saveJobs = (robot)->
  robot.brain.set 'hubot-remind-reminders', BRAIN_JOBS
  robot.brain.save()

module.exports = (robot) ->
  loaded = false
  respondToCommand = (msg, name, at, time, something) ->
    if /^me$/i.test(name.trim())
      users = [msg.message.user]
    else
      users = robot.brain.usersForFuzzyName(name)

    if users.length is 1
      firstLetter = time.substring(0, 1)
      switch firstLetter
        when 's' then timeWord = 'second'
        when 'm' then timeWord = 'minute'
        when 'h' then timeWord = 'hour'
        when 'd' then timeWord = 'day'

      handleNewJob robot, msg, users[0], moment().add(at, timeWord).toDate(), something
    else if users.length > 1
      msg.send "Be more specific, I know #{users.length} people " +
          "named like that: #{(user.name for user in users).join(", ")}"
    else
      msg.send "#{name}? Never heard of 'em"

  # The module is loaded right now
  robot.brain.on 'loaded', ->
    if loaded
      return
    else
      loaded = true
    try
      thingsToRemind = robot.brain.get('hubot-remind-reminders') || []
    catch
      thingsToRemind = []
    console.log('loaded ' + thingsToRemind.length + ' reminders from brain')
    currentDate = new Date()
    thingsToRemind.forEach (thing)->
      if currentDate < thing.pattern
        registerNewJobFromBrain robot, thing.id, thing.pattern, thing.user, thing.message

  robot.respond /(reminders|what are your reminders)/i, (msg) ->
    text = ''
    for id, job of JOBS
      room = job.user.reply_to || job.user.room
      if room == msg.message.user.reply_to or room == msg.message.user.room
        text += "#{id}: @#{room} to \"#{job.message} at #{job.pattern}\"\n"
    if text.length > 0
      msg.send text
    else
      msg.send "Nothing to remind, isn't it?"

  robot.respond /(forget|rm|remove) reminder (\d+)/i, (msg) ->
    reqId = msg.match[2]
    for id, job of JOBS
      if (reqId == id)
        if unregisterJob(robot, reqId)
          msg.send "Reminder #{id} deleted."
        else
          msg.send "I can't forget it, maybe I need a headshrinker"

  robot.respond /remind (.*) to (.*) in (\d+)(se?c?o?n?d?|mi?n?u?t?e?s?|ho?u?r?s?|da?y?s?)/i, (msg) ->
    name = msg.match[1]
    something = msg.match[2]
    at = msg.match[3]
    time = msg.match[4]
    respondToCommand msg, name, at, time, something

  robot.respond /remind to (.*) in (\d+)(se?c?o?n?d?|mi?n?u?t?e?s?|ho?u?r?s?|da?y?s?)/i, (msg) ->
    name = 'me'
    something = msg.match[1]
    at = msg.match[2]
    time = msg.match[3]
    respondToCommand msg, name, at, time, something

  robot.respond /remind (.*) in (\d+)(se?c?o?n?d?|mi?n?u?t?e?s?|ho?u?r?s?|da?y?s?) to (.*)/i, (msg) ->
    name = msg.match[1]
    at = msg.match[2]
    time = msg.match[3]
    something = msg.match[4]
    respondToCommand msg, name, at, time, something

class Job
  constructor: (id, pattern, user, message) ->
    @id = id
    @pattern = pattern
    # cloning user because adapter may touch it later
    clonedUser = {}
    clonedUser[k] = v for k,v of user
    @user = clonedUser
    @message = message

  start: (robot) ->
    @cronjob = new cronJob(@pattern, =>
      @sendMessage robot, ->
      unregisterJob robot, @id
    )
    @cronjob.start()

  stop: ->
    @cronjob.stop()

  serialize: ->
    [@pattern, @user, @message]

  sendMessage: (robot) ->
    envelope = user: @user, room: @user.room
    message = @message
    if @user.mention_name
      message = "Hey @#{envelope.user.mention_name} remember: " + @message
    else
      message = "Hey @#{envelope.user.name} remember: " + @message
    robot.send envelope, message

