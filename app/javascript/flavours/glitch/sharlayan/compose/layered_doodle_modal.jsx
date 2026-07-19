import PropTypes from 'prop-types';

import classNames from 'classnames';

import ImmutablePropTypes from 'react-immutable-proptypes';
import ImmutablePureComponent from 'react-immutable-pure-component';
import { defineMessages } from 'react-intl';
import { connect } from 'react-redux';

import Atrament, { MODE_DISABLED, MODE_DRAW, MODE_ERASE, MODE_FILL } from 'atrament';
import fill from 'atrament/fill';
import { getStroke } from 'perfect-freehand';

import ColorsIcon from '@/material-icons/400-24px/colors.svg?react';
import DeleteIcon from '@/material-icons/400-24px/delete.svg?react';
import EditIcon from '@/material-icons/400-24px/edit.svg?react';
import RedoIcon from '@/material-icons/400-24px/redo.svg?react';
import UndoIcon from '@/material-icons/400-24px/undo.svg?react';
import { doodleSet, uploadCompose } from 'flavours/glitch/actions/compose';
import { Button } from 'flavours/glitch/components/button';
import { Toggle } from 'flavours/glitch/components/form_fields/toggle_field';
import { injectIntl } from 'flavours/glitch/components/intl';

const messages = defineMessages({
  addLayer: { id: 'doodle.add_layer', defaultMessage: 'Add layer' },
  background: { id: 'doodle.background', defaultMessage: 'Background' },
  brush: { id: 'doodle.brush', defaultMessage: 'Brush' },
  brushWidth: { id: 'doodle.brush_width', defaultMessage: 'Brush width' },
  cancel: { id: 'doodle.cancel', defaultMessage: 'Cancel' },
  canvasSize: { id: 'doodle.canvas_size', defaultMessage: 'Canvas size' },
  changeSizeConfirm: { id: 'doodle.change_size_confirm', defaultMessage: 'Change canvas size? This will erase all layers.' },
  clearLayer: { id: 'doodle.clear_layer', defaultMessage: 'Clear layer' },
  clearLayerConfirm: { id: 'doodle.clear_layer_confirm', defaultMessage: 'Clear {name}?' },
  color: { id: 'doodle.color', defaultMessage: 'Color' },
  colorChoice: { id: 'doodle.color_choice', defaultMessage: 'Select {name}' },
  deleteLayer: { id: 'doodle.delete_layer', defaultMessage: 'Delete layer' },
  deleteLayerConfirm: { id: 'doodle.delete_layer_confirm', defaultMessage: 'Delete {name}?' },
  discardConfirm: { id: 'doodle.discard_confirm', defaultMessage: 'Discard doodle? All changes will be lost!' },
  draw: { id: 'doodle.draw', defaultMessage: 'Draw' },
  drawingTools: { id: 'doodle.drawing_tools', defaultMessage: 'Drawing tools' },
  erase: { id: 'doodle.erase', defaultMessage: 'Erase' },
  export: { id: 'doodle.export', defaultMessage: 'Export' },
  fill: { id: 'doodle.fill', defaultMessage: 'Fill' },
  hideLayer: { id: 'doodle.hide_layer', defaultMessage: 'Hide {name}' },
  layerName: { id: 'doodle.layer_name', defaultMessage: 'Layer {number}' },
  layers: { id: 'doodle.layers', defaultMessage: 'Layers' },
  moveLayerDown: { id: 'doodle.move_layer_down', defaultMessage: 'Move layer down' },
  moveLayerUp: { id: 'doodle.move_layer_up', defaultMessage: 'Move layer up' },
  opacity: { id: 'doodle.opacity', defaultMessage: 'Opacity' },
  opacityLabel: { id: 'doodle.opacity_label', defaultMessage: '{name} opacity' },
  pressureSensitivity: { id: 'doodle.pressure_sensitivity', defaultMessage: 'Pressure sensitivity' },
  redo: { id: 'doodle.redo', defaultMessage: 'Redo' },
  rightClickBackground: { id: 'doodle.right_click_background', defaultMessage: 'Right-click sets background' },
  showLayer: { id: 'doodle.show_layer', defaultMessage: 'Show {name}' },
  size480p: { id: 'doodle.size.480p', defaultMessage: '640×480 - 480p' },
  size720p: { id: 'doodle.size.720p', defaultMessage: '720×405 - 16:9' },
  sizeSquare: { id: 'doodle.size.square', defaultMessage: 'Square 500' },
  sizeSvga: { id: 'doodle.size.svga', defaultMessage: '800×600 - SVGA' },
  sizeTootbanner: { id: 'doodle.size.tootbanner', defaultMessage: 'Toot banner' },
  smoothStroke: { id: 'doodle.smooth_stroke', defaultMessage: 'Smooth stroke' },
  texture: { id: 'doodle.texture', defaultMessage: 'Texture' },
  textureChalk: { id: 'doodle.texture.chalk', defaultMessage: 'Chalk' },
  textureInk: { id: 'doodle.texture.ink', defaultMessage: 'Ink' },
  textureMarker: { id: 'doodle.texture.marker', defaultMessage: 'Marker' },
  undo: { id: 'doodle.undo', defaultMessage: 'Undo' },
  width: { id: 'doodle.width', defaultMessage: 'Width' },
});

const COLORS = [
  ['rgb(  0,    0,    0)', 'Black'],
  ['rgb( 21,   21,   21)', '#151515'],
  ['rgb( 38,   38,   38)', 'Gray 15'],
  ['rgb( 42,   42,   42)', '#2A2A2A'],
  ['rgb( 63,   63,   63)', '#3F3F3F'],
  ['rgb( 77,   77,   77)', 'Grey 30'],
  ['rgb( 85,   85,   85)', '#555555'],
  ['rgb(106,  106,  106)', '#6A6A6A'],
  ['rgb(128,  128,  128)', 'Grey 50'],
  ['rgb(148,  148,  148)', '#949494'],
  ['rgb(171,  171,  171)', 'Grey 67'],
  ['rgb(191,  191,  191)', '#BFBFBF'],
  ['rgb(212,  212,  212)', '#D4D4D4'],
  ['rgb(217,  217,  217)', 'Grey 85'],
  ['rgb(233,  233,  233)', '#E9E9E9'],
  ['rgb(255,  255,  255)', 'White'],
  ['rgb( 48,   54,   78)', '#30364E'],
  ['rgb( 30,   30,   35)', '#1E1E23'],
  ['rgb(130,  255,   65)', '#82FF41'],
  ['rgb( 80,  235,   90)', '#50EB5A'],
  ['rgb( 40,  195,  115)', '#28C373'],
  ['rgb( 40,  150,  135)', '#289687'],
  ['rgb( 40,  115,  135)', '#287387'],
  ['rgb( 40,   90,  135)', '#285A87'],
  ['rgb( 30,   60,  110)', '#1E3C6E'],
  ['rgb( 30,   35,   85)', '#1E2355'],
  ['rgb( 40,   40,   90)', '#28285A'],
  ['rgb( 51,   63,  107)', '#333F6B'],
  ['rgb( 69,   86,  148)', '#455694'],
  ['rgb( 96,  105,  136)', '#606988'],
  ['rgb( 90,   80,  120)', '#5A5078'],
  ['rgb( 70,   60,  120)', '#463C78'],
  ['rgb( 55,   45,   90)', '#372D5A'],
  ['rgb(125,   85,  145)', '#7d5591'],
  ['rgb(155,   85,  155)', '#98559b'],
  ['rgb(205,  115,  155)', '#cd739b'],
  ['rgb(177,  121,  124)', '#B1797C'],
  ['rgb(219,  160,  156)', '#DBA09C'],
  ['rgb(221,  181,  161)', '#DDB5A1'],
  ['rgb(251,  201,  190)', '#FBC9BE'],
  ['rgb(251,  220,  192)', '#FBDCC0'],
  ['rgb(128,    0,    0)', 'Maroon'],
  ['rgb(209,    0,    0)', 'English-red'],
  ['rgb(255,   54,   34)', 'Tomato'],
  ['rgb(252,   60,    3)', 'Orange-red'],
  ['rgb(255,  140,  105)', 'Salmon'],
  ['rgb(252,  232,   32)', 'Cadium-yellow'],
  ['rgb(243,  253,   37)', 'Lemon yellow'],
  ['rgb(121,    5,   35)', 'Dark crimson'],
  ['rgb(169,   32,   62)', 'Deep carmine'],
  ['rgb(255,  140,    0)', 'Orange'],
  ['rgb(255,  168,   18)', 'Dark tangerine'],
  ['rgb(217,  144,   88)', 'Persian orange'],
  ['rgb(194,  178,  128)', 'Sand'],
  ['rgb(255,  229,  180)', 'Peach'],
  ['rgb(100,   54,   46)', 'Bole'],
  ['rgb(108,   41,   52)', 'Dark cordovan'],
  ['rgb(163,   65,   44)', 'Chestnut'],
  ['rgb(228,  136,  100)', 'Dark salmon'],
  ['rgb(255,  195,  143)', 'Apricot'],
  ['rgb(255,  219,  188)', 'Unbleached silk'],
  ['rgb(242,  227,  198)', 'Straw'],
  ['rgb( 53,   19,   13)', 'Bistre'],
  ['rgb( 84,   42,   14)', 'Dark chocolate'],
  ['rgb(102,   51,   43)', 'Burnt sienna'],
  ['rgb(184,   66,    0)', 'Sienna'],
  ['rgb(216,  153,   12)', 'Yellow ochre'],
  ['rgb(210,  180,  140)', 'Tan'],
  ['rgb(232,  204,  144)', 'Dark wheat'],
  ['rgb(  0,   49,   83)', 'Prussian blue'],
  ['rgb( 48,   69,  119)', 'Dark grey blue'],
  ['rgb(  0,   71,  171)', 'Cobalt blue'],
  ['rgb( 31,  117,  254)', 'Blue'],
  ['rgb(120,  180,  255)', 'Bright french blue'],
  ['rgb(171,  200,  255)', 'Bright steel blue'],
  ['rgb(208,  231,  255)', 'Ice blue'],
  ['rgb( 30,   51,   58)', 'Medium jungle green'],
  ['rgb( 47,   79,   79)', 'Dark slate grey'],
  ['rgb( 74,  104,   93)', 'Dark grullo green'],
  ['rgb(  0,  128,  128)', 'Teal'],
  ['rgb( 67,  170,  176)', 'Turquoise'],
  ['rgb(109,  174,  199)', 'Cerulean frost'],
  ['rgb(173,  217,  186)', 'Tiffany green'],
  ['rgb( 22,   34,   29)', 'Gray-asparagus'],
  ['rgb( 36,   48,   45)', 'Medium dark teal'],
  ['rgb( 74,  104,   93)', 'Xanadu'],
  ['rgb(119,  198,  121)', 'Mint'],
  ['rgb(175,  205,  182)', 'Timberwolf'],
  ['rgb(185,  245,  246)', 'Celeste'],
  ['rgb(193,  255,  234)', 'Aquamarine'],
  ['rgb( 29,   52,   35)', 'Cal Poly Pomona'],
  ['rgb(  1,   68,   33)', 'Forest green'],
  ['rgb( 42,  128,    0)', 'Napier green'],
  ['rgb(128,  128,    0)', 'Olive'],
  ['rgb( 65,  156,  105)', 'Sea green'],
  ['rgb(189,  246,   29)', 'Green-yellow'],
  ['rgb(231,  244,  134)', 'Bright chartreuse'],
  ['rgb(138,   23,  137)', 'Purple'],
  ['rgb( 78,   39,  138)', 'Violet'],
  ['rgb(193,   75,  110)', 'Dark thulian pink'],
  ['rgb(222,   49,   99)', 'Cerise'],
  ['rgb(255,   20,  147)', 'Deep pink'],
  ['rgb(255,  102,  204)', 'Rose pink'],
  ['rgb(255,  203,  219)', 'Pink'],
  ['rgb(229,   17,    1)', 'RGB Red'],
  ['rgb(  0,  255,    0)', 'RGB Green'],
  ['rgb(  0,    0,  255)', 'RGB Blue'],
  ['rgb(  0,  255,  255)', 'CMYK Cyan'],
  ['rgb(255,    0,  255)', 'CMYK Magenta'],
  ['rgb(255,  255,    0)', 'CMYK Yellow'],
];

const DEFAULT_BACKGROUND_COLOR = 'rgb(255,  255,  255)';

const DOODLE_SIZES = {
  normal: [500, 500, messages.sizeSquare],
  tootbanner: [702, 330, messages.sizeTootbanner],
  s640x480: [640, 480, messages.size480p],
  s800x600: [800, 600, messages.sizeSvga],
  s720x480: [720, 405, messages.size720p],
};

const TEXTURES = [
  ['ink', messages.textureInk],
  ['chalk', messages.textureChalk],
  ['marker', messages.textureMarker],
];

const dataURLtoFile = (dataUrl, filename) => {
  const [header, encoded] = dataUrl.split(',');
  const bytes = atob(encoded);
  const array = new Uint8Array(bytes.length);

  for (let i = 0; i < bytes.length; i++) array[i] = bytes.charCodeAt(i);

  return new File([array], filename, { type: header.match(/:(.*?);/)[1] });
};

const mapStateToProps = state => ({
  options: state.getIn(['compose', 'doodle']),
});

const mapDispatchToProps = dispatch => ({
  setOpt: options => dispatch(doodleSet(options)),
  submit: file => dispatch(uploadCompose([file])),
});

export class LayeredDoodleModal extends ImmutablePureComponent {

  static propTypes = {
    intl: PropTypes.object.isRequired,
    options: ImmutablePropTypes.map,
    onClose: PropTypes.func.isRequired,
    setOpt: PropTypes.func.isRequired,
    submit: PropTypes.func.isRequired,
  };

  state = {
    activeLayerId: null,
    canvasSize: this.props.options?.get('size') ?? 'normal',
    layers: [],
    texture: 'ink',
  };

  get fg () {
    return this.props.options.get('fg');
  }

  set fg (value) {
    this.props.setOpt({ fg: value });
  }

  get bg () {
    return this.props.options.get('bg');
  }

  set bg (value) {
    this.props.setOpt({ bg: value });
  }

  get mode () {
    return this.props.options.get('mode');
  }

  set mode (value) {
    this.props.setOpt({ mode: value });
  }

  get weight () {
    return this.props.options.get('weight');
  }

  set weight (value) {
    this.props.setOpt({ weight: value });
  }

  get opacity () {
    return this.props.options.get('opacity');
  }

  get adaptiveStroke () {
    return this.props.options.get('adaptiveStroke');
  }

  set adaptiveStroke (value) {
    this.props.setOpt({ adaptiveStroke: value });
  }

  get smoothing () {
    return this.props.options.get('smoothing');
  }

  set smoothing (value) {
    this.props.setOpt({ smoothing: value });
  }

  get size () {
    return this.state.canvasSize;
  }

  componentDidMount () {
    window.addEventListener('keydown', this.handleKeyDown, false);
    this.initializeLayers();
  }

  componentDidUpdate () {
    this.updateSketcherSettings();
  }

  componentWillUnmount () {
    window.removeEventListener('keydown', this.handleKeyDown, false);
    this.state.layers.forEach(layer => layer.sketcher.destroy());
  }

  setStackRef = element => {
    this.stack = element;
  };

  makeLayer = (name, { background = false, color, sizeKey = this.size } = {}) => {
    const [width, height] = DOODLE_SIZES[sizeKey];
    const canvas = document.createElement('canvas');
    const sketcher = new Atrament(canvas, { width, height, fill });
    const layer = {
      canvas,
      background,
      color,
      history: { redos: [], undos: [] },
      id: `layer-${Date.now()}-${Math.random()}`,
      name,
      opacity: 100,
      sketcher,
      visible: true,
    };

    canvas.className = 'doodle-modal__canvas';
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    canvas.addEventListener('contextmenu', event => event.preventDefault());
    canvas.addEventListener('pointerdown', event => this.startTextureStroke(layer, event));
    canvas.addEventListener('pointermove', event => this.moveTextureStroke(layer, event));
    canvas.addEventListener('pointerup', event => this.endTextureStroke(layer, event));
    canvas.addEventListener('pointercancel', event => this.endTextureStroke(layer, event));
    sketcher.addEventListener('strokeend', () => {
      if (this.state.activeLayerId === layer.id && this.state.texture !== 'chalk' && this.mode !== 'fill') this.saveLayerSnapshot(layer);
    });
    sketcher.addEventListener('fillend', () => this.saveLayerSnapshot(layer));
    this.stack.appendChild(canvas);
    if (color) {
      const context = canvas.getContext('2d');
      context.fillStyle = color;
      context.fillRect(0, 0, width, height);
    }
    this.saveLayerSnapshot(layer);
    return layer;
  };

  initializeLayers = (sizeKey = this.size) => {
    this.bg = DEFAULT_BACKGROUND_COLOR;
    const background = this.makeLayer(this.props.intl.formatMessage(messages.background), { background: true, color: DEFAULT_BACKGROUND_COLOR, sizeKey });
    const layer = this.makeLayer(this.props.intl.formatMessage(messages.layerName, { number: 1 }), { sizeKey });
    this.setState({ activeLayerId: layer.id, layers: [background, layer] }, this.updateLayerPresentation);
  };

  addLayer = name => {
    const layerName = name ?? this.props.intl.formatMessage(messages.layerName, { number: this.state.layers.filter(layer => !layer.background).length + 1 });
    const layer = this.makeLayer(layerName);
    this.setState(state => ({ activeLayerId: layer.id, layers: [...state.layers, layer] }), this.updateLayerPresentation);
  };

  activeLayer = () => this.state.layers.find(layer => layer.id === this.state.activeLayerId);

  updateLayerPresentation = () => {
    this.state.layers.forEach(layer => {
      layer.canvas.style.opacity = `${layer.opacity / 100}`;
      layer.canvas.style.pointerEvents = layer.id === this.state.activeLayerId && layer.visible ? 'auto' : 'none';
      layer.canvas.style.visibility = layer.visible ? 'visible' : 'hidden';
    });
    this.updateSketcherSettings();
  };

  updateSketcherSettings = () => {
    const layer = this.activeLayer();

    if (!layer) return;

    const { sketcher } = layer;
    sketcher.color = this.fg;
    sketcher.weight = this.weight;
    sketcher.smoothing = this.smoothing ? 1.25 : 0.85;
    sketcher.adaptiveStroke = this.adaptiveStroke;
    sketcher.pressureLow = 0.35;
    sketcher.pressureHigh = 1.8;
    sketcher.pressureSmoothing = 0.35;
    sketcher.mode = this.state.texture === 'chalk' ? MODE_DISABLED : this.mode === 'erase' ? MODE_ERASE : this.mode === 'fill' ? MODE_FILL : MODE_DRAW;
    layer.canvas.getContext('2d').globalAlpha = this.state.texture === 'marker' ? 0.35 : this.opacity;
  };

  saveLayerSnapshot = layer => {
    const context = layer.canvas.getContext('2d', { willReadFrequently: true });
    const snapshot = context.getImageData(0, 0, layer.canvas.width, layer.canvas.height);
    layer.history.undos.push(snapshot);
    if (layer.history.undos.length > 30) layer.history.undos.shift();
    layer.history.redos = [];
  };

  restoreLayerSnapshot = (layer, snapshot) => {
    layer.sketcher.clear();
    layer.canvas.getContext('2d').putImageData(snapshot, 0, 0);
  };

  undo = () => {
    const layer = this.activeLayer();

    if (!layer || layer.history.undos.length < 2) return;

    layer.history.redos.push(layer.history.undos.pop());
    this.restoreLayerSnapshot(layer, layer.history.undos[layer.history.undos.length - 1]);
  };

  redo = () => {
    const layer = this.activeLayer();

    if (!layer || layer.history.redos.length === 0) return;

    const snapshot = layer.history.redos.pop();
    layer.history.undos.push(snapshot);
    this.restoreLayerSnapshot(layer, snapshot);
  };

  texturePattern = (context, color) => {
    const tile = document.createElement('canvas');
    tile.width = 12;
    tile.height = 12;
    const texture = tile.getContext('2d');
    texture.fillStyle = color;
    texture.globalAlpha = 0.55;
    for (let i = 0; i < 16; i++) texture.fillRect(Math.random() * 12, Math.random() * 12, 1, 1);
    return context.createPattern(tile, 'repeat');
  };

  drawTextureStroke = () => {
    const stroke = this.textureStroke;
    const layer = this.activeLayer();

    if (!stroke || !layer || stroke.layerId !== layer.id) return;

    const context = layer.canvas.getContext('2d');
    const outline = getStroke(stroke.points, { size: this.weight, smoothing: 0.6, streamline: 0.35, thinning: 0.65, simulatePressure: false });
    context.putImageData(stroke.base, 0, 0);
    context.save();
    context.beginPath();
    outline.forEach(([x, y], index) => index === 0 ? context.moveTo(x, y) : context.lineTo(x, y));
    context.closePath();
    context.clip();
    context.globalAlpha = this.opacity;
    context.fillStyle = stroke.pattern;
    context.fillRect(0, 0, layer.canvas.width, layer.canvas.height);
    context.restore();
  };

  startTextureStroke = (layer, event) => {
    if (this.state.texture !== 'chalk' || this.mode !== 'draw' || layer.id !== this.state.activeLayerId) return;

    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    const context = layer.canvas.getContext('2d', { willReadFrequently: true });
    this.textureStroke = {
      base: context.getImageData(0, 0, layer.canvas.width, layer.canvas.height),
      layerId: layer.id,
      pattern: this.texturePattern(context, this.fg),
      pointerId: event.pointerId,
      points: [[event.offsetX, event.offsetY, event.pressure || 0.5]],
    };
    this.drawTextureStroke();
  };

  moveTextureStroke = (layer, event) => {
    if (!this.textureStroke || this.textureStroke.layerId !== layer.id || this.textureStroke.pointerId !== event.pointerId) return;

    this.textureStroke.points.push([event.offsetX, event.offsetY, event.pressure || 0.5]);
    this.drawTextureStroke();
  };

  endTextureStroke = (layer, event) => {
    if (!this.textureStroke || this.textureStroke.layerId !== layer.id || this.textureStroke.pointerId !== event.pointerId) return;

    this.drawTextureStroke();
    this.textureStroke = null;
    this.saveLayerSnapshot(layer);
  };

  setMode = mode => {
    this.mode = mode;
    this.updateSketcherSettings();
  };

  setTexture = event => {
    this.setState({ texture: event.target.value }, this.updateSketcherSettings);
  };

  setWeight = event => {
    this.weight = Math.max(1, Number(event.target.value) || 1);
  };

  toggleSmoothing = event => {
    this.smoothing = event.target.checked;
  };

  toggleAdaptive = event => {
    this.adaptiveStroke = event.target.checked;
  };

  setColor = event => {
    this.fg = event.currentTarget.dataset.color;
  };

  setBackground = event => {
    event.preventDefault();
    const color = event.currentTarget.dataset.color;
    const background = this.state.layers.find(layer => layer.background);
    this.bg = color;

    if (background) {
      background.color = color;
      background.sketcher.clear();
      const context = background.canvas.getContext('2d');
      context.fillStyle = color;
      context.fillRect(0, 0, background.canvas.width, background.canvas.height);
      this.saveLayerSnapshot(background);
    }
  };

  selectLayer = id => {
    this.setState({ activeLayerId: id }, this.updateLayerPresentation);
  };

  toggleLayer = id => {
    this.setState(state => ({ layers: state.layers.map(layer => layer.id === id ? { ...layer, visible: !layer.visible } : layer) }), this.updateLayerPresentation);
  };

  setLayerOpacity = (id, event) => {
    const opacity = Number(event.target.value);
    this.setState(state => ({ layers: state.layers.map(layer => layer.id === id ? { ...layer, opacity } : layer) }), this.updateLayerPresentation);
  };

  removeLayer = () => {
    const layer = this.activeLayer();

    if (!layer || layer.background || !confirm(this.props.intl.formatMessage(messages.deleteLayerConfirm, { name: layer.name }))) return;

    layer.sketcher.destroy();
    layer.canvas.remove();
    this.setState(state => {
      const layers = state.layers.filter(item => item.id !== layer.id);
      return { activeLayerId: layers[layers.length - 1].id, layers };
    }, this.updateLayerPresentation);
  };

  clearLayer = () => {
    const layer = this.activeLayer();

    if (!layer || !confirm(this.props.intl.formatMessage(messages.clearLayerConfirm, { name: layer.name }))) return;

    layer.sketcher.clear();
    if (layer.background) {
      const context = layer.canvas.getContext('2d');
      context.fillStyle = layer.color;
      context.fillRect(0, 0, layer.canvas.width, layer.canvas.height);
    }
    this.saveLayerSnapshot(layer);
  };

  moveLayer = direction => {
    const index = this.state.layers.findIndex(layer => layer.id === this.state.activeLayerId);
    const target = index + direction;

    if (index < 0 || this.state.layers[index].background || target < 1 || target >= this.state.layers.length) return;

    const layers = [...this.state.layers];
    [layers[index], layers[target]] = [layers[target], layers[index]];
    layers.forEach(layer => this.stack.appendChild(layer.canvas));
    this.setState({ layers });
  };

  changeSize = event => {
    const size = event.target.value;

    if (size === this.size || !confirm(this.props.intl.formatMessage(messages.changeSizeConfirm))) return;

    this.state.layers.forEach(layer => {
      layer.sketcher.destroy();
      layer.canvas.remove();
    });
    this.props.setOpt({ size });
    this.setState({ activeLayerId: null, canvasSize: size, layers: [] }, () => this.initializeLayers(size));
  };

  handleKeyDown = event => {
    if (event.target.nodeName === 'INPUT' || event.target.nodeName === 'SELECT') return;

    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'z') {
      event.preventDefault();
      if (event.shiftKey) this.redo(); else this.undo();
    }

    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'y') {
      event.preventDefault();
      this.redo();
    }
  };

  onDoneButton = () => {
    const [background] = this.state.layers;
    const { width, height } = background.canvas;
    const result = document.createElement('canvas');
    result.width = width;
    result.height = height;
    const context = result.getContext('2d');
    this.state.layers.forEach(layer => {
      if (!layer.visible) return;
      context.globalAlpha = layer.opacity / 100;
      context.drawImage(layer.canvas, 0, 0);
    });
    context.globalAlpha = 1;
    this.props.submit(dataURLtoFile(result.toDataURL('image/png'), 'doodle.png'));
    this.props.onClose();
  };

  onCancelButton = () => {
    if (this.state.layers.some(layer => layer.history.undos.length > 1) && !confirm(this.props.intl.formatMessage(messages.discardConfirm))) return;
    this.props.onClose();
  };

  render () {
    const { activeLayerId, layers, texture } = this.state;
    const { intl } = this.props;
    const activeLayerIndex = layers.findIndex(layer => layer.id === activeLayerId);
    const activeLayer = layers[activeLayerIndex];

    return (
      <div className='modal-root__modal doodle-modal doodle-modal--layered doodle-editor'>
        <header className='doodle-editor__header'>
          <div className='doodle-editor__toolbar' role='toolbar' aria-label={intl.formatMessage(messages.drawingTools)}>
            <button type='button' className={classNames('doodle-editor__tool', { active: this.mode === 'draw' })} aria-pressed={this.mode === 'draw'} onClick={() => this.setMode('draw')} title={intl.formatMessage(messages.draw)}><EditIcon /><span>{intl.formatMessage(messages.draw)}</span></button>
            <button type='button' className={classNames('doodle-editor__tool', { active: this.mode === 'erase' })} aria-pressed={this.mode === 'erase'} onClick={() => this.setMode('erase')} title={intl.formatMessage(messages.erase)}><DeleteIcon /><span>{intl.formatMessage(messages.erase)}</span></button>
            <button type='button' className={classNames('doodle-editor__tool', { active: this.mode === 'fill' })} aria-pressed={this.mode === 'fill'} onClick={() => this.setMode('fill')} title={intl.formatMessage(messages.fill)}><ColorsIcon /><span>{intl.formatMessage(messages.fill)}</span></button>
            <span className='doodle-editor__toolbar-separator' />
            <button type='button' className='doodle-editor__tool doodle-editor__tool--icon' onClick={this.undo} title={intl.formatMessage(messages.undo)} aria-label={intl.formatMessage(messages.undo)}><UndoIcon /></button>
            <button type='button' className='doodle-editor__tool doodle-editor__tool--icon' onClick={this.redo} title={intl.formatMessage(messages.redo)} aria-label={intl.formatMessage(messages.redo)}><RedoIcon /></button>
            <button type='button' className='doodle-editor__tool doodle-editor__tool--icon' onClick={this.clearLayer} title={intl.formatMessage(messages.clearLayer)} aria-label={intl.formatMessage(messages.clearLayer)}><DeleteIcon /></button>
          </div>
          <label className='doodle-editor__size'>
            <select aria-label={intl.formatMessage(messages.canvasSize)} onChange={this.changeSize} value={this.size}>
              {Object.entries(DOODLE_SIZES).map(([key, value]) => <option key={key} value={key}>{intl.formatMessage(value[2])}</option>)}
            </select>
          </label>
        </header>

        <div className='doodle-editor__body'>
          <main className='doodle-editor__workspace'>
            <div className='doodle-editor__canvas-frame'>
              <div className='doodle-modal__canvas-stack' key={this.size} ref={this.setStackRef} />
            </div>
          </main>

          <aside className='doodle-editor__inspector'>
            <section className='doodle-editor__panel doodle-layer-controls'>
              <div className='doodle-editor__panel-title'><span>{intl.formatMessage(messages.layers)}</span><button type='button' onClick={() => this.addLayer()} title={intl.formatMessage(messages.addLayer)} aria-label={intl.formatMessage(messages.addLayer)}>+</button></div>
              <div className='doodle-layer-list'>
                {layers.slice().reverse().map(layer => <div className={classNames('doodle-layer-row', { active: layer.id === activeLayerId })} key={layer.id}>
                  <button type='button' className='doodle-layer-row__visibility' onClick={() => this.toggleLayer(layer.id)} aria-label={intl.formatMessage(layer.visible ? messages.hideLayer : messages.showLayer, { name: layer.name })} title={intl.formatMessage(layer.visible ? messages.hideLayer : messages.showLayer, { name: layer.name })}>{layer.visible ? '●' : '○'}</button>
                  <button type='button' className='doodle-layer-row__name' onClick={() => this.selectLayer(layer.id)}><span className={classNames('doodle-layer-row__thumbnail', { background: layer.background })} style={layer.background ? { background: layer.color } : undefined} />{layer.name}</button>
                  <span className='doodle-layer-row__opacity'>{layer.opacity}%</span>
                </div>)}
              </div>
              <div className='doodle-layer-controls__buttons'>
                <button type='button' disabled={!activeLayer || activeLayer.background || activeLayerIndex === layers.length - 1} onClick={() => this.moveLayer(1)} title={intl.formatMessage(messages.moveLayerUp)}>↑</button>
                <button type='button' disabled={!activeLayer || activeLayer.background || activeLayerIndex <= 1} onClick={() => this.moveLayer(-1)} title={intl.formatMessage(messages.moveLayerDown)}>↓</button>
                <button type='button' disabled={!activeLayer || activeLayer.background} onClick={this.removeLayer} title={intl.formatMessage(messages.deleteLayer)}>{intl.formatMessage(messages.deleteLayer)}</button>
              </div>
              {activeLayer && <label className='doodle-editor__opacity'>{intl.formatMessage(messages.opacity)} <input aria-label={intl.formatMessage(messages.opacityLabel, { name: activeLayer.name })} type='range' min='0' max='100' value={activeLayer.opacity} onChange={event => this.setLayerOpacity(activeLayer.id, event)} /><output>{activeLayer.opacity}%</output></label>}
            </section>

            <section className='doodle-editor__panel'>
              <div className='doodle-editor__panel-title'><span>{intl.formatMessage(messages.color)}</span><small>{intl.formatMessage(messages.rightClickBackground)}</small></div>
              <div className='doodle-palette'>
                {COLORS.map(([color, name], index) => <button type='button' key={`${color}-${index}`} style={{ backgroundColor: color }} onClick={this.setColor} onContextMenu={this.setBackground} data-color={color} title={intl.formatMessage(messages.colorChoice, { name })} aria-label={intl.formatMessage(messages.colorChoice, { name })} className={classNames({ foreground: this.fg === color, background: this.bg === color })} />)}
              </div>
            </section>

            <section className='doodle-editor__panel doodle-editor__settings'>
              <div className='doodle-editor__panel-title'><span>{intl.formatMessage(messages.brush)}</span></div>
              <label>{intl.formatMessage(messages.texture)}<select value={texture} onChange={this.setTexture}>{TEXTURES.map(([value, label]) => <option key={value} value={value}>{intl.formatMessage(label)}</option>)}</select></label>
              <label>{intl.formatMessage(messages.width)}<div className='doodle-editor__field-pair'><input aria-label={intl.formatMessage(messages.brushWidth)} type='range' min='1' max='100' value={this.weight} onChange={this.setWeight} /><input aria-label={intl.formatMessage(messages.brushWidth)} type='number' min='1' max='100' value={this.weight} onChange={this.setWeight} /></div></label>
              <div className='setting-toggle'><Toggle id='doodle-smoothing' checked={this.smoothing} onChange={this.toggleSmoothing} size={16} /><label htmlFor='doodle-smoothing' className='setting-toggle__label'>{intl.formatMessage(messages.smoothStroke)}</label></div>
              <div className='setting-toggle'><Toggle id='doodle-pressure-sensitivity' checked={this.adaptiveStroke} onChange={this.toggleAdaptive} size={16} /><label htmlFor='doodle-pressure-sensitivity' className='setting-toggle__label'>{intl.formatMessage(messages.pressureSensitivity)}</label></div>
            </section>
          </aside>
        </div>

        <footer className='doodle-editor__footer'>
          <span>PNG · RGBA · {DOODLE_SIZES[this.size][0]} × {DOODLE_SIZES[this.size][1]}</span>
          <div><Button text={intl.formatMessage(messages.cancel)} secondary onClick={this.onCancelButton} /><Button text={intl.formatMessage(messages.export)} onClick={this.onDoneButton} /></div>
        </footer>
      </div>
    );
  }

}

export default injectIntl(connect(mapStateToProps, mapDispatchToProps)(LayeredDoodleModal));
