# frozen_string_literal: true

class MisskeyCompat::ReversiEngine
  BLACK = true
  WHITE = false
  VOID = :void

  DEFAULT_MAP = [
    '--------',
    '--------',
    '--------',
    '---wb---',
    '---bw---',
    '--------',
    '--------',
    '--------',
  ].freeze

  STONES = { '-' => nil, 'b' => BLACK, 'w' => WHITE }.freeze
  DIRECTIONS = [[0, -1], [1, -1], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1]].freeze

  Log = Struct.new(:time, :player, :operation, :pos, keyword_init: true)

  attr_reader :map_width, :map_height, :board, :turn, :prev_pos, :prev_color

  def self.restore(map:, llotheo:, can_put_everywhere:, looped_board:, logs:)
    game = new(map, llotheo: llotheo, can_put_everywhere: can_put_everywhere, looped_board: looped_board)
    deserialize_logs(logs).each { |log| game.put_stone(log.pos) if log.operation == 'put' }
    game
  end

  def self.serialize_logs(logs)
    logs.each_with_index.map do |log, index|
      delta = index.zero? ? log.time : log.time - logs[index - 1].time
      [delta, log.player ? 1 : 0, 0, log.pos]
    end
  end

  def self.deserialize_logs(logs)
    time = 0
    Array(logs).filter_map do |entry|
      time += entry[0]
      Log.new(time: time, player: entry[1] == 1, operation: 'put', pos: entry[3]) if entry[2].zero?
    end
  end

  def initialize(map, llotheo: false, can_put_everywhere: false, looped_board: false)
    @llotheo = llotheo
    @can_put_everywhere = can_put_everywhere
    @looped_board = looped_board
    @map_width = map[0].length
    @map_height = map.length
    cells = map.join.chars
    @board = cells.map { |cell| STONES.fetch(cell, VOID) }
    @cells = cells.map { |cell| STONES.key?(cell) ? :empty : :null }
    @turn = BLACK
    @prev_pos = -1
    @prev_color = nil
    @turn = can_put_somewhere?(WHITE) ? WHITE : nil unless can_put_somewhere?(BLACK)
  end

  def black_count
    @board.count(BLACK)
  end

  def white_count
    @board.count(WHITE)
  end

  def put_stone(pos)
    color = @turn
    return if color.nil?

    @prev_pos = pos
    @prev_color = color
    @board[pos] = color
    effects(color, pos).each { |effect| @board[effect] = color }
    calc_turn
  end

  def can_put?(color, pos)
    return false unless pos.is_a?(Integer) && pos >= 0 && pos < @board.size
    return false unless @board[pos].nil?
    return map_cell(pos) == :empty if @can_put_everywhere

    effects(color, pos).any?
  end

  def can_put_somewhere?(color)
    @board.each_index.any? { |pos| can_put?(color, pos) }
  end

  def puttable_places(color)
    @board.each_index.select { |pos| can_put?(color, pos) }
  end

  def effects(color, init_pos)
    DIRECTIONS.flat_map { |step_x, step_y| effects_in_line(color, init_pos, step_x, step_y) }
  end

  def ended?
    @turn.nil?
  end

  def winner
    return unless ended?
    return if black_count == white_count

    @llotheo == (black_count > white_count) ? WHITE : BLACK
  end

  def crc32
    json = JSON.generate({ board: @board.map { |cell| cell == VOID ? nil : cell }, turn: @turn })
    value = Zlib.crc32(json)
    value >= 2**31 ? value - (2**32) : value
  end

  private

  def calc_turn
    @turn = if can_put_somewhere?(!@prev_color)
              !@prev_color
            elsif can_put_somewhere?(@prev_color)
              @prev_color
            end
  end

  def map_cell(pos)
    x, y = pos_to_xy(pos)
    return :null if x.negative? || y.negative? || x >= @map_width || y >= @map_height

    @cells[pos]
  end

  def pos_to_xy(pos)
    [pos % @map_width, pos / @map_width]
  end

  def xy_to_pos(col, row)
    col + (row * @map_width)
  end

  def effects_in_line(color, init_pos, step_x, step_y)
    found = []
    x, y = pos_to_xy(init_pos)

    loop do
      x += step_x
      y += step_y

      if @looped_board
        x %= @map_width
        y %= @map_height
        return found if xy_to_pos(x, y) == init_pos
      elsif x == -1 || y == -1 || x == @map_width || y == @map_height
        return []
      end

      pos = xy_to_pos(x, y)
      return [] if map_cell(pos) == :null

      stone = @board[pos]
      return [] if stone.nil?
      return found if stone == color

      found << pos
    end
  end
end
