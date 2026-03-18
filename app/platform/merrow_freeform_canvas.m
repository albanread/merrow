#import "merrow_freeform_canvas.h"

static NSColor *MerrowFreeformNSColor(MerrowFreeformColor color) {
    return [NSColor colorWithCalibratedRed:color.r / 255.0
                                     green:color.g / 255.0
                                      blue:color.b / 255.0
                                     alpha:color.a / 255.0];
}

static NSBezierPath *MerrowFreeformPolygonPath(const CGPoint *points, NSUInteger count) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    if (count == 0) return path;
    [path moveToPoint:points[0]];
    for (NSUInteger idx = 1; idx < count; idx += 1) {
        [path lineToPoint:points[idx]];
    }
    [path closePath];
    return path;
}

static void MerrowFreeformDrawArrow(CGPoint from, CGPoint tip, NSColor *color) {
    const CGFloat dx = tip.x - from.x;
    const CGFloat dy = tip.y - from.y;
    const CGFloat len = hypot(dx, dy);
    if (len < 0.001) return;

    const CGFloat ux = dx / len;
    const CGFloat uy = dy / len;
    const CGFloat px = -uy;
    const CGFloat py = ux;
    const CGFloat size = 10.0;
    const CGFloat halfWidth = size * 0.45;

    CGPoint points[3] = {
        tip,
        { tip.x - ux * size + px * halfWidth, tip.y - uy * size + py * halfWidth },
        { tip.x - ux * size - px * halfWidth, tip.y - uy * size - py * halfWidth },
    };

    [color setFill];
    [MerrowFreeformPolygonPath(points, 3) fill];
}

static NSString *MerrowFreeformShapeName(uint32_t shape) {
    switch (shape) {
        case 0: return @"rectangle";
        case 1: return @"rounded rectangle";
        case 2: return @"diamond";
        case 3: return @"circle";
        case 4: return @"hexagon";
        case 5: return @"cylinder";
        case 6: return @"stadium";
        case 7: return @"trapezoid";
        case 8: return @"inverted trapezoid";
        case 9: return @"parallelogram";
        case 10: return @"inverse parallelogram";
        case 11: return @"subroutine";
        default: return @"shape";
    }
}

static void MerrowFreeformColorComponents(NSColor *color, CGFloat *red, CGFloat *green, CGFloat *blue, CGFloat *alpha) {
    NSColor *resolved = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] ?: [NSColor blackColor];
    [resolved getRed:red green:green blue:blue alpha:alpha];
}

static NSString *MerrowFreeformHexColor(NSColor *color) {
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 1.0;
    MerrowFreeformColorComponents(color, &red, &green, &blue, &alpha);
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (unsigned int)lrint(MAX(0.0, MIN(red, 1.0)) * 255.0),
            (unsigned int)lrint(MAX(0.0, MIN(green, 1.0)) * 255.0),
            (unsigned int)lrint(MAX(0.0, MIN(blue, 1.0)) * 255.0)];
}

static NSString *MerrowFreeformSVGPaintAttributes(NSString *kind, NSColor *color) {
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 1.0;
    MerrowFreeformColorComponents(color, &red, &green, &blue, &alpha);
    NSString *hex = [NSString stringWithFormat:@"#%02X%02X%02X",
                     (unsigned int)lrint(MAX(0.0, MIN(red, 1.0)) * 255.0),
                     (unsigned int)lrint(MAX(0.0, MIN(green, 1.0)) * 255.0),
                     (unsigned int)lrint(MAX(0.0, MIN(blue, 1.0)) * 255.0)];
    if (alpha >= 0.999) {
        return [NSString stringWithFormat:@"%@=\"%@\"", kind, hex];
    }
    return [NSString stringWithFormat:@"%@=\"%@\" %@-opacity=\"%.3f\"", kind, hex, kind, alpha];
}

static NSString *MerrowFreeformEscapeXML(NSString *text) {
    if (text.length == 0) return @"";
    NSMutableString *escaped = [text mutableCopy];
    [escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"'" withString:@"&apos;" options:0 range:NSMakeRange(0, escaped.length)];
    return escaped;
}

static NSString *MerrowFreeformPointList(const CGPoint *points, NSUInteger count) {
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger idx = 0; idx < count; idx += 1) {
        [parts addObject:[NSString stringWithFormat:@"%.2f,%.2f", points[idx].x, points[idx].y]];
    }
    return [parts componentsJoinedByString:@" "];
}

static NSString *MerrowFreeformArrowPointList(CGPoint from, CGPoint tip) {
    const CGFloat dx = tip.x - from.x;
    const CGFloat dy = tip.y - from.y;
    const CGFloat len = hypot(dx, dy);
    if (len < 0.001) return nil;

    const CGFloat ux = dx / len;
    const CGFloat uy = dy / len;
    const CGFloat px = -uy;
    const CGFloat py = ux;
    const CGFloat size = 10.0;
    const CGFloat halfWidth = size * 0.45;

    CGPoint points[3] = {
        tip,
        { tip.x - ux * size + px * halfWidth, tip.y - uy * size + py * halfWidth },
        { tip.x - ux * size - px * halfWidth, tip.y - uy * size - py * halfWidth },
    };
    return MerrowFreeformPointList(points, 3);
}

static NSUInteger MerrowFreeformLineCount(NSString *text) {
    if (text.length == 0) return 0;
    return [[text componentsSeparatedByString:@"\n"] count];
}

static CGFloat MerrowFreeformClassHeaderHeight(NSString *label, NSString *subtitle, CGFloat labelFontSize) {
    const NSUInteger subtitleLines = MerrowFreeformLineCount(subtitle);
    const CGFloat subtitleHeight = subtitleLines > 0 ? subtitleLines * 14.0 + 6.0 : 0.0;
    const CGFloat titleHeight = MAX(labelFontSize, 15.0) + 10.0;
    return MAX(44.0, subtitleHeight + titleHeight + 12.0);
}

static NSInteger MerrowFreeformClampEndStyle(NSInteger style) {
    return MAX(0, MIN(style, 5));
}



@interface MerrowFreeformNodeRecord : NSObject
@property (nonatomic, copy) NSString *nodeId;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *attributesText;
@property (nonatomic, copy) NSString *methodsText;
@property (nonatomic, copy) NSString *parentSubgraphId;
@property (nonatomic, assign) uint32_t shape;
@property (nonatomic, assign) CGFloat x;
@property (nonatomic, assign) CGFloat y;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, assign) CGFloat height;
@property (nonatomic, strong) NSColor *fillColor;
@property (nonatomic, strong) NSColor *bodyFillColor;
@property (nonatomic, strong) NSColor *strokeColor;
@property (nonatomic, assign) CGFloat strokeWidth;
@property (nonatomic, strong) NSColor *labelColor;
@property (nonatomic, assign) CGFloat labelFontSize;
@end

@implementation MerrowFreeformNodeRecord
@end

@interface MerrowFreeformEdgeRecord : NSObject
@property (nonatomic, copy) NSString *sourceId;
@property (nonatomic, copy) NSString *targetId;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, strong) NSColor *strokeColor;
@property (nonatomic, assign) CGFloat thickness;
@property (nonatomic, assign) uint32_t lineStyle;
@property (nonatomic, assign) BOOL hasArrow;
@property (nonatomic, assign) BOOL hasSourceArrow;
@property (nonatomic, assign) uint32_t sourceEndStyle;
@property (nonatomic, assign) uint32_t targetEndStyle;
@end

@implementation MerrowFreeformEdgeRecord
@end

@interface MerrowFreeformSubgraphRecord : NSObject
@property (nonatomic, copy) NSString *subgraphId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *parentSubgraphId;
@property (nonatomic, assign) CGFloat x;
@property (nonatomic, assign) CGFloat y;
@property (nonatomic, assign) CGFloat width;
@property (nonatomic, assign) CGFloat height;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, strong) NSColor *fillColor;
@property (nonatomic, strong) NSColor *strokeColor;
@property (nonatomic, assign) CGFloat strokeWidth;
@property (nonatomic, assign) CGFloat titleX;
@property (nonatomic, assign) CGFloat titleY;
@property (nonatomic, assign) CGFloat titleFontSize;
@property (nonatomic, strong) NSColor *titleColor;
@end

@implementation MerrowFreeformSubgraphRecord
@end

typedef struct {
    CGFloat scale;
    CGFloat offsetX;
    CGFloat offsetY;
} MerrowFreeformViewport;

typedef NS_ENUM(NSInteger, MerrowFreeformResizeHandle) {
    MerrowFreeformResizeHandleNone = 0,
    MerrowFreeformResizeHandleNorthWest,
    MerrowFreeformResizeHandleNorth,
    MerrowFreeformResizeHandleNorthEast,
    MerrowFreeformResizeHandleEast,
    MerrowFreeformResizeHandleSouthEast,
    MerrowFreeformResizeHandleSouth,
    MerrowFreeformResizeHandleSouthWest,
    MerrowFreeformResizeHandleWest,
};

typedef NS_ENUM(NSInteger, MerrowFreeformEdgeEndpointHandle) {
    MerrowFreeformEdgeEndpointHandleNone = 0,
    MerrowFreeformEdgeEndpointHandleSource,
    MerrowFreeformEdgeEndpointHandleTarget,
};

typedef struct {
    CGFloat left;
    CGFloat top;
    CGFloat right;
    CGFloat bottom;
} MerrowFreeformInsets;

@interface MerrowFreeformCanvasComponent ()
@property (nonatomic, strong) NSMutableArray<MerrowFreeformSubgraphRecord *> *subgraphs;
@property (nonatomic, strong) NSMutableArray<MerrowFreeformNodeRecord *> *nodes;
@property (nonatomic, strong) NSMutableArray<MerrowFreeformEdgeRecord *> *edges;
@property (nonatomic, strong) NSMutableDictionary<NSString *, MerrowFreeformSubgraphRecord *> *subgraphsById;
@property (nonatomic, strong) NSMutableDictionary<NSString *, MerrowFreeformNodeRecord *> *nodesById;
@property (nonatomic, weak) MerrowFreeformNodeRecord *selectedNode;
@property (nonatomic, weak) MerrowFreeformSubgraphRecord *selectedSubgraph;
@property (nonatomic, weak) MerrowFreeformEdgeRecord *selectedEdge;
@property (nonatomic, assign) BOOL draggingSelection;
@property (nonatomic, assign) BOOL resizingSelection;
@property (nonatomic, assign) BOOL draggingEdgeEndpoint;
@property (nonatomic, assign) CGPoint lastDragContentPoint;
@property (nonatomic, assign) CGPoint resizeStartContentPoint;
@property (nonatomic, assign) NSRect resizeInitialFrame;
@property (nonatomic, assign) MerrowFreeformResizeHandle activeResizeHandle;
@property (nonatomic, assign) MerrowFreeformEdgeEndpointHandle activeEdgeEndpointHandle;
@property (nonatomic, assign) CGPoint edgeDragPreviewPoint;
@property (nonatomic, copy) NSString *edgeDragOriginalSourceId;
@property (nonatomic, copy) NSString *edgeDragOriginalTargetId;
@property (nonatomic, copy) NSString *edgeDragHoverObjectId;
@property (nonatomic, assign) MerrowFreeformInsertionKind insertionKind;
@property (nonatomic, assign) uint32_t insertionNodeShape;
@property (nonatomic, copy) NSString *connectorSourceObjectId;
@property (nonatomic, strong) NSUndoManager *canvasUndoManager;
@property (nonatomic, assign) BOOL applyingUndoRedo;
@property (nonatomic, strong) NSData *pendingDragUndoSnapshot;
@property (nonatomic, copy) NSString *pendingDragUndoActionName;
@property (nonatomic, strong) NSColor *canvasBackgroundColor;
@property (nonatomic, assign) CGFloat documentWidth;
@property (nonatomic, assign) CGFloat documentHeight;
@property (nonatomic, assign) MerrowFreeformGraphType graphType;
@property (nonatomic, assign) CGFloat zoom;
@property (nonatomic, assign) CGPoint pan;
@property (nonatomic, assign) NSPoint lastViewDragPoint;
@property (nonatomic, assign) BOOL draggingCanvas;
@property (nonatomic, strong) NSMagnificationGestureRecognizer *magnifyRecognizer;
@end

@implementation MerrowFreeformCanvasComponent

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _subgraphs = [NSMutableArray array];
        _nodes = [NSMutableArray array];
        _edges = [NSMutableArray array];
        _subgraphsById = [NSMutableDictionary dictionary];
        _nodesById = [NSMutableDictionary dictionary];
        _canvasBackgroundColor = [NSColor whiteColor];
        _documentWidth = 1200.0;
        _documentHeight = 800.0;
        _graphType = MerrowFreeformGraphTypeFlowchart;
        _zoom = 1.0;
        _pan = CGPointZero;
        self.wantsLayer = YES;
        self.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.96 green:0.97 blue:0.98 alpha:1.0].CGColor;
        _magnifyRecognizer = [[NSMagnificationGestureRecognizer alloc] initWithTarget:self action:@selector(handleMagnifyGesture:)];
        [self addGestureRecognizer:_magnifyRecognizer];
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (NSUndoManager *)undoManager {
    if (!self.canvasUndoManager) {
        self.canvasUndoManager = [[NSUndoManager alloc] init];
        self.canvasUndoManager.levelsOfUndo = 200;
    }
    return self.canvasUndoManager;
}

- (NSString *)selectionSummary {
    if (!self.selectedNode && !self.selectedSubgraph) {
        if (self.selectedEdge) {
            NSString *edgeLabel = self.selectedEdge.label.length > 0 ? self.selectedEdge.label : [NSString stringWithFormat:@"%@ -> %@", self.selectedEdge.sourceId ?: @"?", self.selectedEdge.targetId ?: @"?"];
            return [NSString stringWithFormat:@"Selected connector: %@", edgeLabel];
        }
        return @"No selection";
    }
    if (self.selectedSubgraph) {
        return [NSString stringWithFormat:@"Selected group: %@", self.selectedSubgraph.title.length > 0 ? self.selectedSubgraph.title : self.selectedSubgraph.subgraphId];
    }
    return [NSString stringWithFormat:@"Selected: %@", self.selectedNode.label.length > 0 ? self.selectedNode.label : self.selectedNode.nodeId];
}

- (NSString *)displayNameForNode:(MerrowFreeformNodeRecord *)node {
    NSString *name = node.label.length > 0 ? node.label : node.nodeId;
    return [NSString stringWithFormat:@"Shape: %@", name.length > 0 ? name : @"Untitled"];
}

- (BOOL)isInvisibleAnchorNode:(MerrowFreeformNodeRecord *)node {
    if (!node) return NO;
    if (node.label.length > 0) return NO;
    if (![node.nodeId hasPrefix:@"message-"]) return NO;

    CGFloat fillAlpha = 1.0;
    CGFloat strokeAlpha = 1.0;
    [[node.fillColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] getRed:nil green:nil blue:nil alpha:&fillAlpha];
    [[node.strokeColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] getRed:nil green:nil blue:nil alpha:&strokeAlpha];
    return fillAlpha <= 0.001 && strokeAlpha <= 0.001 && node.strokeWidth <= 0.001 && node.width <= 12.0 && node.height <= 12.0;
}

- (NSString *)displayNameForSubgraph:(MerrowFreeformSubgraphRecord *)subgraph {
    NSString *name = subgraph.title.length > 0 ? subgraph.title : subgraph.subgraphId;
    return [NSString stringWithFormat:@"Group: %@", name.length > 0 ? name : @"Untitled"];
}

- (NSString *)displayNameForObjectId:(NSString *)objectId {
    if (objectId.length == 0) {
        return @"";
    }
    MerrowFreeformNodeRecord *node = self.nodesById[objectId];
    if (node) {
        return [self displayNameForNode:node];
    }
    MerrowFreeformSubgraphRecord *subgraph = self.subgraphsById[objectId];
    if (subgraph) {
        return [self displayNameForSubgraph:subgraph];
    }
    return objectId;
}

- (NSString *)insertionSummary {
    switch (self.insertionKind) {
        case MerrowFreeformInsertionKindNode:
            return [NSString stringWithFormat:@"Click the canvas to place a new %@. Press Escape to cancel.", MerrowFreeformShapeName(self.insertionNodeShape)];
        case MerrowFreeformInsertionKindSubgraph:
            return @"Click the canvas to place a new group. Press Escape to cancel.";
        case MerrowFreeformInsertionKindConnector: {
            NSString *sourceName = [self displayNameForObjectId:self.connectorSourceObjectId];
            return [NSString stringWithFormat:@"Click a target shape or group to create a connector from %@. Press Escape to cancel.", sourceName.length > 0 ? sourceName : @"the selected object"];
        }
        default:
            return @"Choose Add Shape or Add Group, then click the canvas to place it.";
    }
}

- (NSString *)selectedConnectableObjectId {
    if (self.selectedSubgraph.subgraphId.length > 0) {
        return self.selectedSubgraph.subgraphId;
    }
    if (self.selectedNode.nodeId.length > 0) {
        return self.selectedNode.nodeId;
    }
    return nil;
}

- (BOOL)hasSelectedNode {
    return self.selectedNode != nil;
}

- (BOOL)hasSelectedSubgraph {
    return self.selectedSubgraph != nil;
}

- (BOOL)hasSelectedEdge {
    return self.selectedEdge != nil;
}

- (BOOL)insertionModeActive {
    return self.insertionKind != MerrowFreeformInsertionKindNone;
}

- (NSArray<NSDictionary *> *)connectableObjects {
    NSMutableArray<NSDictionary *> *objects = [NSMutableArray arrayWithCapacity:self.subgraphs.count + self.nodes.count];
    for (MerrowFreeformSubgraphRecord *subgraph in self.subgraphs) {
        if (subgraph.subgraphId.length == 0) continue;
        [objects addObject:@{
            @"id": subgraph.subgraphId,
            @"title": [self displayNameForSubgraph:subgraph],
        }];
    }
    for (MerrowFreeformNodeRecord *node in self.nodes) {
        if (node.nodeId.length == 0) continue;
        if ([self isInvisibleAnchorNode:node]) continue;
        [objects addObject:@{
            @"id": node.nodeId,
            @"title": [self displayNameForNode:node],
        }];
    }
    return objects;
}

- (NSString *)selectedNodeLabel {
    if (self.selectedSubgraph) {
        return self.selectedSubgraph.title ?: @"";
    }
    return self.selectedNode.label ?: @"";
}

- (CGFloat)canvasBackgroundOpacity {
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 1.0;
    [[self.canvasBackgroundColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] getRed:&red green:&green blue:&blue alpha:&alpha];
    return alpha;
}

- (NSColor *)selectedNodeFillColor {
    if (self.selectedSubgraph) {
        return self.selectedSubgraph.fillColor ?: [NSColor colorWithCalibratedWhite:0.96 alpha:1.0];
    }
    return self.selectedNode.fillColor ?: [NSColor whiteColor];
}

- (NSString *)selectedNodeSubtitle {
    return self.selectedNode.subtitle ?: @"";
}

- (NSString *)selectedNodeAttributesText {
    return self.selectedNode.attributesText ?: @"";
}

- (NSString *)selectedNodeMethodsText {
    return self.selectedNode.methodsText ?: @"";
}

- (NSColor *)selectedNodeBodyFillColor {
    return self.selectedNode.bodyFillColor ?: self.selectedNode.fillColor ?: [NSColor whiteColor];
}

- (NSColor *)selectedNodeStrokeColor {
    if (self.selectedSubgraph) {
        return self.selectedSubgraph.strokeColor ?: [NSColor colorWithCalibratedWhite:0.55 alpha:1.0];
    }
    return self.selectedNode.strokeColor ?: [NSColor blackColor];
}

- (CGFloat)selectedNodeStrokeWidth {
    if (self.selectedSubgraph) {
        return self.selectedSubgraph.strokeWidth;
    }
    return self.selectedNode ? self.selectedNode.strokeWidth : 1.0;
}

- (NSString *)selectedEdgeLabel {
    return self.selectedEdge.label ?: @"";
}

- (NSColor *)selectedEdgeStrokeColor {
    return self.selectedEdge.strokeColor ?: [NSColor blackColor];
}

- (CGFloat)selectedEdgeThickness {
    return self.selectedEdge ? self.selectedEdge.thickness : 1.0;
}

- (NSInteger)selectedEdgeLineStyle {
    return self.selectedEdge ? (NSInteger)self.selectedEdge.lineStyle : 0;
}

- (NSInteger)selectedEdgeArrowMode {
    if (!self.selectedEdge) return 0;
    if (self.selectedEdge.hasArrow && self.selectedEdge.hasSourceArrow) return 3;
    if (self.selectedEdge.hasArrow) return 1;
    if (self.selectedEdge.hasSourceArrow) return 2;
    return 0;
}

- (NSInteger)selectedEdgeSourceEndStyle {
    return self.selectedEdge ? (NSInteger)self.selectedEdge.sourceEndStyle : 0;
}

- (NSInteger)selectedEdgeTargetEndStyle {
    return self.selectedEdge ? (NSInteger)self.selectedEdge.targetEndStyle : 0;
}

- (void)clearDocument {
    [self.subgraphs removeAllObjects];
    [self.nodes removeAllObjects];
    [self.edges removeAllObjects];
    [self.subgraphsById removeAllObjects];
    [self.nodesById removeAllObjects];
    self.insertionKind = MerrowFreeformInsertionKindNone;
    self.connectorSourceObjectId = nil;
    self.draggingEdgeEndpoint = NO;
    self.activeEdgeEndpointHandle = MerrowFreeformEdgeEndpointHandleNone;
    self.edgeDragHoverObjectId = nil;
    self.edgeDragOriginalSourceId = nil;
    self.edgeDragOriginalTargetId = nil;
    [self discardPendingUndoGroup];
    self.selectedNode = nil;
    self.selectedSubgraph = nil;
    self.selectedEdge = nil;
    self.documentWidth = 1200.0;
    self.documentHeight = 800.0;
    self.graphType = MerrowFreeformGraphTypeFlowchart;
    if (!self.applyingUndoRedo) {
        [self.undoManager removeAllActions];
    }
    [self notifySelectionChanged];
    [self setNeedsDisplay:YES];
}

- (void)beginInsertingNodeWithShape:(uint32_t)shape {
    self.insertionNodeShape = shape;
    self.insertionKind = MerrowFreeformInsertionKindNode;
    self.connectorSourceObjectId = nil;
    self.draggingSelection = NO;
    [self notifySelectionChanged];
    [self setNeedsDisplay:YES];
}

- (void)beginInsertingSubgraph {
    self.insertionKind = MerrowFreeformInsertionKindSubgraph;
    self.connectorSourceObjectId = nil;
    self.draggingSelection = NO;
    [self notifySelectionChanged];
    [self setNeedsDisplay:YES];
}

- (BOOL)beginInsertingConnectorFromSelectedObject {
    return [self beginInsertingConnectorFromObjectId:self.selectedConnectableObjectId];
}

- (BOOL)beginInsertingConnectorFromObjectId:(NSString *)sourceId {
    if (sourceId.length == 0) {
        return NO;
    }
    if (!self.nodesById[sourceId] && !self.subgraphsById[sourceId]) {
        return NO;
    }
    if (self.connectableObjects.count < 2) {
        return NO;
    }

    self.connectorSourceObjectId = [sourceId copy];
    self.insertionKind = MerrowFreeformInsertionKindConnector;
    self.draggingSelection = NO;
    self.draggingEdgeEndpoint = NO;
    self.activeEdgeEndpointHandle = MerrowFreeformEdgeEndpointHandleNone;
    self.edgeDragHoverObjectId = nil;

    MerrowFreeformNodeRecord *node = self.nodesById[sourceId];
    MerrowFreeformSubgraphRecord *subgraph = self.subgraphsById[sourceId];
    self.selectedNode = node;
    self.selectedSubgraph = subgraph;
    self.selectedEdge = nil;
    [self notifySelectionChanged];
    [self setNeedsDisplay:YES];
    return YES;
}

- (void)cancelInsertionMode {
    if (self.insertionKind == MerrowFreeformInsertionKindNone) return;
    self.insertionKind = MerrowFreeformInsertionKindNone;
    self.connectorSourceObjectId = nil;
    self.draggingSelection = NO;
    [self notifySelectionChanged];
    [self setNeedsDisplay:YES];
}

- (BOOL)createConnectorFromObjectId:(NSString *)sourceId toObjectId:(NSString *)targetId {
    if (sourceId.length == 0 || targetId.length == 0 || [sourceId isEqualToString:targetId]) {
        return NO;
    }
    if ((!self.nodesById[sourceId] && !self.subgraphsById[sourceId]) || (!self.nodesById[targetId] && !self.subgraphsById[targetId])) {
        return NO;
    }

    NSData *undoSnapshot = [self snapshotDataForUndo];
    MerrowFreeformEdgeRecord *edge = [[MerrowFreeformEdgeRecord alloc] init];
    edge.sourceId = [sourceId copy];
    edge.targetId = [targetId copy];
    edge.label = @"";
    edge.strokeColor = [NSColor colorWithCalibratedRed:0.18 green:0.21 blue:0.26 alpha:1.0];
    edge.thickness = 2.0;
    edge.lineStyle = 0;
    edge.hasArrow = YES;
    edge.hasSourceArrow = NO;
    edge.sourceEndStyle = 0;
    edge.targetEndStyle = self.graphType == MerrowFreeformGraphTypeClass ? 4 : 0;
    [self.edges addObject:edge];

    self.insertionKind = MerrowFreeformInsertionKindNone;
    self.connectorSourceObjectId = nil;
    self.selectedNode = nil;
    self.selectedSubgraph = nil;
    self.selectedEdge = edge;
    [self registerUndoSnapshot:undoSnapshot actionName:@"Add Connector"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
    return YES;
}

- (void)updateCanvasBackgroundColor:(NSColor *)color {
    if (!color) return;
    NSData *undoSnapshot = [self snapshotDataForUndo];
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 1.0;
    [[color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] getRed:&red green:&green blue:&blue alpha:&alpha];
    CGFloat currentOpacity = self.canvasBackgroundOpacity;
    self.canvasBackgroundColor = [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:currentOpacity];
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Background Color"];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)updateCanvasBackgroundOpacity:(CGFloat)opacity {
    NSData *undoSnapshot = [self snapshotDataForUndo];
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 1.0;
    [[self.canvasBackgroundColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] getRed:&red green:&green blue:&blue alpha:&alpha];
    self.canvasBackgroundColor = [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:MAX(0.0, MIN(opacity, 1.0))];
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Background Opacity"];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)loadEditableGraph:(const MerrowFreeformGraphSnapshot *)graph {
    [self clearDocument];
    if (!graph) {
        self.canvasBackgroundColor = [NSColor whiteColor];
        [self resetView];
        return;
    }

    self.canvasBackgroundColor = MerrowFreeformNSColor(graph->background);
    self.documentWidth = MAX((CGFloat)graph->width, 600.0);
    self.documentHeight = MAX((CGFloat)graph->height, 400.0);
    self.graphType = (MerrowFreeformGraphType)MAX(0, MIN((NSInteger)graph->graph_type, (NSInteger)MerrowFreeformGraphTypeClass));
    [self resetView];

    for (size_t idx = 0; idx < graph->subgraph_count; idx += 1) {
        const MerrowFreeformSubgraphSnapshot *snapshot = &graph->subgraphs[idx];
        MerrowFreeformSubgraphRecord *subgraph = [[MerrowFreeformSubgraphRecord alloc] init];
        subgraph.subgraphId = snapshot->id ? [NSString stringWithUTF8String:snapshot->id] : @"";
        subgraph.title = snapshot->title ? [NSString stringWithUTF8String:snapshot->title] : @"";
        subgraph.parentSubgraphId = snapshot->parent_subgraph_id ? [NSString stringWithUTF8String:snapshot->parent_subgraph_id] : nil;
        subgraph.x = snapshot->x;
        subgraph.y = snapshot->y;
        subgraph.width = snapshot->width;
        subgraph.height = snapshot->height;
        subgraph.cornerRadius = snapshot->corner_radius;
        subgraph.fillColor = MerrowFreeformNSColor(snapshot->fill);
        subgraph.strokeColor = MerrowFreeformNSColor(snapshot->stroke);
        subgraph.strokeWidth = snapshot->stroke_width;
        subgraph.titleX = snapshot->title_x;
        subgraph.titleY = snapshot->title_y;
        subgraph.titleFontSize = snapshot->title_font_size;
        subgraph.titleColor = MerrowFreeformNSColor(snapshot->title_color);
        [self.subgraphs addObject:subgraph];
        if (subgraph.subgraphId.length > 0) {
            self.subgraphsById[subgraph.subgraphId] = subgraph;
        }
    }

    for (size_t idx = 0; idx < graph->node_count; idx += 1) {
        const MerrowFreeformNodeSnapshot *snapshot = &graph->nodes[idx];
        MerrowFreeformNodeRecord *node = [[MerrowFreeformNodeRecord alloc] init];
        node.nodeId = snapshot->id ? [NSString stringWithUTF8String:snapshot->id] : @"";
        node.label = snapshot->label ? [NSString stringWithUTF8String:snapshot->label] : @"";
        node.subtitle = snapshot->subtitle ? [NSString stringWithUTF8String:snapshot->subtitle] : @"";
        node.attributesText = snapshot->attributes_text ? [NSString stringWithUTF8String:snapshot->attributes_text] : @"";
        node.methodsText = snapshot->methods_text ? [NSString stringWithUTF8String:snapshot->methods_text] : @"";
        node.parentSubgraphId = snapshot->parent_subgraph_id ? [NSString stringWithUTF8String:snapshot->parent_subgraph_id] : nil;
        node.shape = snapshot->shape;
        node.x = snapshot->x;
        node.y = snapshot->y;
        node.width = snapshot->width;
        node.height = snapshot->height;
        node.fillColor = MerrowFreeformNSColor(snapshot->fill);
        node.bodyFillColor = MerrowFreeformNSColor(snapshot->body_fill);
        node.strokeColor = MerrowFreeformNSColor(snapshot->stroke);
        node.strokeWidth = snapshot->stroke_width;
        node.labelColor = MerrowFreeformNSColor(snapshot->label_color);
        node.labelFontSize = snapshot->label_font_size;
        [self.nodes addObject:node];
        if (node.nodeId.length > 0) {
            self.nodesById[node.nodeId] = node;
        }
    }

    for (size_t idx = 0; idx < graph->edge_count; idx += 1) {
        const MerrowFreeformEdgeSnapshot *snapshot = &graph->edges[idx];
        MerrowFreeformEdgeRecord *edge = [[MerrowFreeformEdgeRecord alloc] init];
        edge.sourceId = snapshot->source_id ? [NSString stringWithUTF8String:snapshot->source_id] : @"";
        edge.targetId = snapshot->target_id ? [NSString stringWithUTF8String:snapshot->target_id] : @"";
        edge.label = snapshot->label ? [NSString stringWithUTF8String:snapshot->label] : @"";
        edge.strokeColor = MerrowFreeformNSColor(snapshot->color);
        edge.thickness = snapshot->thickness;
        edge.lineStyle = snapshot->line_style;
        edge.hasArrow = snapshot->has_arrow != 0;
        edge.hasSourceArrow = snapshot->has_source_arrow != 0;
        edge.sourceEndStyle = snapshot->source_end_style;
        edge.targetEndStyle = snapshot->target_end_style;
        [self.edges addObject:edge];
    }

    [self setNeedsDisplay:YES];
}

- (void)updateSelectedNodeLabel:(NSString *)label {
    NSData *undoSnapshot = [self snapshotDataForUndo];
    if (self.selectedSubgraph) {
        self.selectedSubgraph.title = [label copy] ?: @"";
    } else {
        if (!self.selectedNode) return;
        self.selectedNode.label = [label copy] ?: @"";
    }
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Label"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)updateSelectedNodeFillColor:(NSColor *)color {
    if (!color) return;
    NSData *undoSnapshot = [self snapshotDataForUndo];
    if (self.selectedSubgraph) {
        self.selectedSubgraph.fillColor = color;
    } else {
        if (!self.selectedNode) return;
        self.selectedNode.fillColor = color;
    }
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Fill Color"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)updateSelectedNodeBodyFillColor:(NSColor *)color {
    if (!self.selectedNode || !color) return;
    NSData *undoSnapshot = [self snapshotDataForUndo];
    self.selectedNode.bodyFillColor = color;
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Body Fill Color"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)updateSelectedNodeStrokeColor:(NSColor *)color {
    if (!color) return;
    NSData *undoSnapshot = [self snapshotDataForUndo];
    if (self.selectedSubgraph) {
        self.selectedSubgraph.strokeColor = color;
    } else {
        if (!self.selectedNode) return;
        self.selectedNode.strokeColor = color;
    }
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Stroke Color"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)updateSelectedNodeStrokeWidth:(CGFloat)strokeWidth {
    const CGFloat clamped = MAX(1.0, MIN(strokeWidth, 12.0));
    NSData *undoSnapshot = [self snapshotDataForUndo];
    if (self.selectedSubgraph) {
        self.selectedSubgraph.strokeWidth = clamped;
    } else {
        if (!self.selectedNode) return;
        self.selectedNode.strokeWidth = clamped;
    }
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Stroke Width"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)updateSelectedNodeSubtitle:(NSString *)subtitle {
    if (!self.selectedNode) return;
    NSData *undoSnapshot = [self snapshotDataForUndo];
    self.selectedNode.subtitle = [subtitle copy] ?: @"";
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Subtitle"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)updateSelectedNodeAttributesText:(NSString *)text {
    if (!self.selectedNode) return;
    NSData *undoSnapshot = [self snapshotDataForUndo];
    self.selectedNode.attributesText = [text copy] ?: @"";
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Attributes"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)updateSelectedNodeMethodsText:(NSString *)text {
    if (!self.selectedNode) return;
    NSData *undoSnapshot = [self snapshotDataForUndo];
    self.selectedNode.methodsText = [text copy] ?: @"";
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Methods"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)updateSelectedEdgeLabel:(NSString *)label {
    if (!self.selectedEdge) return;
    NSData *undoSnapshot = [self snapshotDataForUndo];
    self.selectedEdge.label = [label copy] ?: @"";
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Connector Label"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)updateSelectedEdgeStrokeColor:(NSColor *)color {
    if (!self.selectedEdge || !color) return;
    NSData *undoSnapshot = [self snapshotDataForUndo];
    self.selectedEdge.strokeColor = color;
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Connector Color"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)updateSelectedEdgeThickness:(CGFloat)thickness {
    if (!self.selectedEdge) return;
    NSData *undoSnapshot = [self snapshotDataForUndo];
    self.selectedEdge.thickness = MAX(1.0, MIN(thickness, 12.0));
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Connector Thickness"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)updateSelectedEdgeLineStyle:(NSInteger)lineStyle {
    if (!self.selectedEdge) return;
    NSData *undoSnapshot = [self snapshotDataForUndo];
    self.selectedEdge.lineStyle = (uint32_t)MAX(0, MIN(lineStyle, 3));
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Connector Pattern"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)updateSelectedEdgeArrowMode:(NSInteger)arrowMode {
    if (!self.selectedEdge) return;
    NSData *undoSnapshot = [self snapshotDataForUndo];
    switch (arrowMode) {
        case 0:
            self.selectedEdge.hasArrow = NO;
            self.selectedEdge.hasSourceArrow = NO;
            if (self.graphType == MerrowFreeformGraphTypeClass) {
                self.selectedEdge.sourceEndStyle = 0;
                self.selectedEdge.targetEndStyle = 0;
            }
            break;
        case 1:
            self.selectedEdge.hasArrow = YES;
            self.selectedEdge.hasSourceArrow = NO;
            if (self.graphType == MerrowFreeformGraphTypeClass) {
                self.selectedEdge.sourceEndStyle = 0;
                self.selectedEdge.targetEndStyle = 4;
            }
            break;
        case 2:
            self.selectedEdge.hasArrow = NO;
            self.selectedEdge.hasSourceArrow = YES;
            if (self.graphType == MerrowFreeformGraphTypeClass) {
                self.selectedEdge.sourceEndStyle = 4;
                self.selectedEdge.targetEndStyle = 0;
            }
            break;
        default:
            self.selectedEdge.hasArrow = YES;
            self.selectedEdge.hasSourceArrow = YES;
            if (self.graphType == MerrowFreeformGraphTypeClass) {
                self.selectedEdge.sourceEndStyle = 4;
                self.selectedEdge.targetEndStyle = 4;
            }
            break;
    }
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Connector Arrows"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)updateSelectedEdgeSourceEndStyle:(NSInteger)style {
    if (!self.selectedEdge) return;
    NSData *undoSnapshot = [self snapshotDataForUndo];
    self.selectedEdge.sourceEndStyle = (uint32_t)MerrowFreeformClampEndStyle(style);
    self.selectedEdge.hasSourceArrow = self.selectedEdge.sourceEndStyle != 0;
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Source Endpoint"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)updateSelectedEdgeTargetEndStyle:(NSInteger)style {
    if (!self.selectedEdge) return;
    NSData *undoSnapshot = [self snapshotDataForUndo];
    self.selectedEdge.targetEndStyle = (uint32_t)MerrowFreeformClampEndStyle(style);
    self.selectedEdge.hasArrow = self.selectedEdge.targetEndStyle != 0;
    [self registerUndoSnapshot:undoSnapshot actionName:@"Edit Target Endpoint"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)notifySelectionChanged {
    if ([self.delegate respondsToSelector:@selector(freeformCanvasComponentDidChangeSelection:)]) {
        [self.delegate freeformCanvasComponentDidChangeSelection:self];
    }
}

- (void)notifyDocumentMutation {
    if ([self.delegate respondsToSelector:@selector(freeformCanvasComponentDidMutateDocument:)]) {
        [self.delegate freeformCanvasComponentDidMutateDocument:self];
    }
}

- (NSData *)snapshotDataForUndo {
    NSError *error = nil;
    NSData *data = [self serializedDocumentDataWithError:&error];
    return data;
}

- (void)applyUndoSnapshotData:(NSData *)snapshot actionName:(NSString *)actionName {
    if (!snapshot) return;

    NSData *inverseSnapshot = [self snapshotDataForUndo];
    self.applyingUndoRedo = YES;
    NSError *error = nil;
    BOOL loaded = [self loadSerializedDocumentData:snapshot error:&error];
    self.applyingUndoRedo = NO;
    if (!loaded) {
        return;
    }

    if (inverseSnapshot) {
        [[self.undoManager prepareWithInvocationTarget:self] applyUndoSnapshotData:inverseSnapshot actionName:actionName];
        if (actionName.length > 0) {
            [self.undoManager setActionName:actionName];
        }
    }

    [self notifyDocumentMutation];
}

- (void)registerUndoSnapshot:(NSData *)snapshot actionName:(NSString *)actionName {
    if (!snapshot || self.applyingUndoRedo) return;
    [[self.undoManager prepareWithInvocationTarget:self] applyUndoSnapshotData:snapshot actionName:actionName];
    if (actionName.length > 0) {
        [self.undoManager setActionName:actionName];
    }
}

- (void)beginUndoGroupingForAction:(NSString *)actionName {
    if (self.pendingDragUndoSnapshot || self.applyingUndoRedo) return;
    self.pendingDragUndoSnapshot = [self snapshotDataForUndo];
    self.pendingDragUndoActionName = [actionName copy];
}

- (void)commitPendingUndoGroupIfNeeded {
    if (!self.pendingDragUndoSnapshot) return;
    NSData *currentSnapshot = [self snapshotDataForUndo];
    if (![self.pendingDragUndoSnapshot isEqualToData:currentSnapshot]) {
        [self registerUndoSnapshot:self.pendingDragUndoSnapshot actionName:self.pendingDragUndoActionName ?: @"Edit Freeform Object"];
    }
    self.pendingDragUndoSnapshot = nil;
    self.pendingDragUndoActionName = nil;
}

- (void)discardPendingUndoGroup {
    self.pendingDragUndoSnapshot = nil;
    self.pendingDragUndoActionName = nil;
}

- (NSString *)uniqueObjectIdentifierWithPrefix:(NSString *)prefix {
    NSString *uuid = NSUUID.UUID.UUIDString.lowercaseString ?: @"item";
    return [NSString stringWithFormat:@"%@-%@", prefix ?: @"item", uuid];
}

- (CGSize)defaultSizeForNodeShape:(uint32_t)shape {
    switch (shape) {
        case 2:
            return CGSizeMake(124.0, 84.0);
        case 3:
            return CGSizeMake(104.0, 104.0);
        case 4:
            return CGSizeMake(144.0, 84.0);
        case 5:
        case 6:
            return CGSizeMake(148.0, 80.0);
        case 7:
        case 8:
        case 9:
        case 10:
        case 11:
            return CGSizeMake(152.0, 78.0);
        default:
            return CGSizeMake(144.0, 76.0);
    }
}

- (CGPoint)clampedCenterPoint:(CGPoint)point forSize:(CGSize)size {
    const CGFloat halfWidth = MIN(size.width / 2.0, self.documentWidth / 2.0);
    const CGFloat halfHeight = MIN(size.height / 2.0, self.documentHeight / 2.0);
    const CGFloat minX = halfWidth;
    const CGFloat minY = halfHeight;
    const CGFloat maxX = MAX(self.documentWidth - halfWidth, minX);
    const CGFloat maxY = MAX(self.documentHeight - halfHeight, minY);
    return CGPointMake(MAX(minX, MIN(point.x, maxX)), MAX(minY, MIN(point.y, maxY)));
}

- (CGPoint)clampedOriginPoint:(CGPoint)point forSize:(CGSize)size {
    const CGFloat maxX = MAX(self.documentWidth - size.width, 0.0);
    const CGFloat maxY = MAX(self.documentHeight - size.height, 0.0);
    return CGPointMake(MAX(0.0, MIN(point.x, maxX)), MAX(0.0, MIN(point.y, maxY)));
}

- (MerrowFreeformSubgraphRecord *)preferredParentSubgraphForInsertionAtPoint:(CGPoint)point {
    if (self.selectedSubgraph.subgraphId.length > 0) {
        return self.selectedSubgraph;
    }
    MerrowFreeformSubgraphRecord *container = [self subgraphAtContentPoint:point preferContainingRegion:YES];
    return container.subgraphId.length > 0 ? container : nil;
}

- (void)placePendingNodeAtContentPoint:(CGPoint)contentPoint {
    NSData *undoSnapshot = [self snapshotDataForUndo];
    const CGSize size = [self defaultSizeForNodeShape:self.insertionNodeShape];
    const CGPoint center = [self clampedCenterPoint:contentPoint forSize:size];
    MerrowFreeformSubgraphRecord *parent = [self preferredParentSubgraphForInsertionAtPoint:contentPoint];

    MerrowFreeformNodeRecord *node = [[MerrowFreeformNodeRecord alloc] init];
    node.nodeId = [self uniqueObjectIdentifierWithPrefix:@"node"];
    node.label = @"New node";
    node.parentSubgraphId = parent.subgraphId.length > 0 ? parent.subgraphId : nil;
    node.shape = self.insertionNodeShape;
    node.x = center.x;
    node.y = center.y;
    node.width = size.width;
    node.height = size.height;
    node.fillColor = [NSColor colorWithCalibratedWhite:1.0 alpha:1.0];
    node.strokeColor = [NSColor colorWithCalibratedRed:0.21 green:0.25 blue:0.30 alpha:1.0];
    node.strokeWidth = 2.0;
    node.labelColor = [NSColor colorWithCalibratedRed:0.21 green:0.25 blue:0.30 alpha:1.0];
    node.labelFontSize = 14.0;

    [self.nodes addObject:node];
    self.nodesById[node.nodeId] = node;

    self.insertionKind = MerrowFreeformInsertionKindNone;
    self.selectedSubgraph = nil;
    self.selectedEdge = nil;
    self.selectedNode = node;
    [self registerUndoSnapshot:undoSnapshot actionName:@"Add Shape"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)placePendingSubgraphAtContentPoint:(CGPoint)contentPoint {
    NSData *undoSnapshot = [self snapshotDataForUndo];
    const CGSize size = CGSizeMake(260.0, 170.0);
    const CGPoint origin = [self clampedOriginPoint:CGPointMake(contentPoint.x - size.width / 2.0,
                                                               contentPoint.y - size.height / 2.0)
                                           forSize:size];
    MerrowFreeformSubgraphRecord *parent = [self preferredParentSubgraphForInsertionAtPoint:contentPoint];

    MerrowFreeformSubgraphRecord *subgraph = [[MerrowFreeformSubgraphRecord alloc] init];
    subgraph.subgraphId = [self uniqueObjectIdentifierWithPrefix:@"group"];
    subgraph.title = @"New group";
    subgraph.parentSubgraphId = parent.subgraphId.length > 0 ? parent.subgraphId : nil;
    subgraph.x = origin.x;
    subgraph.y = origin.y;
    subgraph.width = size.width;
    subgraph.height = size.height;
    subgraph.cornerRadius = 18.0;
    subgraph.fillColor = [NSColor colorWithCalibratedRed:0.95 green:0.97 blue:0.99 alpha:1.0];
    subgraph.strokeColor = [NSColor colorWithCalibratedRed:0.55 green:0.60 blue:0.68 alpha:1.0];
    subgraph.strokeWidth = 2.0;
    subgraph.titleX = origin.x + 14.0;
    subgraph.titleY = origin.y + 18.0;
    subgraph.titleFontSize = 14.0;
    subgraph.titleColor = [NSColor colorWithCalibratedRed:0.24 green:0.26 blue:0.30 alpha:1.0];

    [self.subgraphs addObject:subgraph];
    self.subgraphsById[subgraph.subgraphId] = subgraph;

    self.insertionKind = MerrowFreeformInsertionKindNone;
    self.selectedNode = nil;
    self.selectedEdge = nil;
    self.selectedSubgraph = subgraph;
    [self registerUndoSnapshot:undoSnapshot actionName:@"Add Group"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (BOOL)deleteCurrentSelection {
    NSData *undoSnapshot = [self snapshotDataForUndo];
    if (self.selectedEdge) {
        MerrowFreeformEdgeRecord *edge = self.selectedEdge;
        self.selectedEdge = nil;
        [self.edges removeObject:edge];
        [self registerUndoSnapshot:undoSnapshot actionName:@"Delete Connector"];
        [self notifySelectionChanged];
        [self notifyDocumentMutation];
        [self setNeedsDisplay:YES];
        return YES;
    }

    if (self.selectedNode) {
        MerrowFreeformNodeRecord *node = self.selectedNode;
        NSString *nodeId = node.nodeId ?: @"";
        self.selectedNode = nil;
        [self.nodes removeObject:node];
        if (nodeId.length > 0) {
            [self.nodesById removeObjectForKey:nodeId];
            NSIndexSet *edgeIndexes = [self.edges indexesOfObjectsPassingTest:^BOOL(MerrowFreeformEdgeRecord * _Nonnull edge, NSUInteger idx, BOOL * _Nonnull stop) {
                (void)idx;
                (void)stop;
                return [edge.sourceId isEqualToString:nodeId] || [edge.targetId isEqualToString:nodeId];
            }];
            if (edgeIndexes.count > 0) {
                [self.edges removeObjectsAtIndexes:edgeIndexes];
            }
        }
        [self registerUndoSnapshot:undoSnapshot actionName:@"Delete Shape"];
        [self notifySelectionChanged];
        [self notifyDocumentMutation];
        [self setNeedsDisplay:YES];
        return YES;
    }

    if (self.selectedSubgraph) {
        MerrowFreeformSubgraphRecord *subgraph = self.selectedSubgraph;
        NSString *subgraphId = subgraph.subgraphId ?: @"";
        NSString *parentId = subgraph.parentSubgraphId;
        self.selectedSubgraph = nil;
        [self.subgraphs removeObject:subgraph];
        if (subgraphId.length > 0) {
            [self.subgraphsById removeObjectForKey:subgraphId];
            NSIndexSet *edgeIndexes = [self.edges indexesOfObjectsPassingTest:^BOOL(MerrowFreeformEdgeRecord * _Nonnull edge, NSUInteger idx, BOOL * _Nonnull stop) {
                (void)idx;
                (void)stop;
                return [edge.sourceId isEqualToString:subgraphId] || [edge.targetId isEqualToString:subgraphId];
            }];
            if (edgeIndexes.count > 0) {
                [self.edges removeObjectsAtIndexes:edgeIndexes];
            }
            for (MerrowFreeformNodeRecord *node in self.nodes) {
                if ([node.parentSubgraphId isEqualToString:subgraphId]) {
                    node.parentSubgraphId = parentId;
                }
            }
            for (MerrowFreeformSubgraphRecord *child in self.subgraphs) {
                if ([child.parentSubgraphId isEqualToString:subgraphId]) {
                    child.parentSubgraphId = parentId;
                }
            }
        }
        [self registerUndoSnapshot:undoSnapshot actionName:@"Delete Group"];
        [self notifySelectionChanged];
        [self notifyDocumentMutation];
        [self setNeedsDisplay:YES];
        return YES;
    }

    return NO;
}

- (IBAction)deleteSelectedObject:(id)sender {
    (void)sender;
    [self deleteCurrentSelection];
}

- (IBAction)startConnectorFromSelection:(id)sender {
    NSString *sourceId = nil;
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        id representedObject = [(NSMenuItem *)sender representedObject];
        if ([representedObject isKindOfClass:[NSString class]]) {
            sourceId = representedObject;
        }
    }
    if (sourceId.length == 0) {
        sourceId = self.selectedConnectableObjectId;
    }
    [self beginInsertingConnectorFromObjectId:sourceId];
}

- (MerrowFreeformViewport)viewport {
    const CGFloat contentWidth = MAX(self.documentWidth, 1.0);
    const CGFloat contentHeight = MAX(self.documentHeight, 1.0);
    const CGFloat availableWidth = MAX(self.bounds.size.width - 32.0, 64.0);
    const CGFloat availableHeight = MAX(self.bounds.size.height - 32.0, 64.0);
    const CGFloat fitScaleX = availableWidth / contentWidth;
    const CGFloat fitScaleY = availableHeight / contentHeight;
    const CGFloat fitScale = MAX(MIN(fitScaleX, fitScaleY), 0.01);
    const CGFloat scale = MAX(fitScale * self.zoom, 0.01);
    const CGFloat offsetX = floor((self.bounds.size.width - contentWidth * scale) * 0.5 + self.pan.x);
    const CGFloat offsetY = floor((self.bounds.size.height - contentHeight * scale) * 0.5 + self.pan.y);
    return (MerrowFreeformViewport){ .scale = scale, .offsetX = offsetX, .offsetY = offsetY };
}

- (void)resetView {
    self.zoom = 1.0;
    self.pan = CGPointZero;
}

- (void)adjustPanByViewDeltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY {
    self.pan = CGPointMake(self.pan.x + deltaX, self.pan.y + deltaY);
}

- (void)adjustZoomByFactor:(CGFloat)factor {
    const CGFloat nextZoom = self.zoom * factor;
    self.zoom = fmax(0.25, fmin(nextZoom, 8.0));
}

- (CGPoint)contentPointForViewPoint:(NSPoint)viewPoint {
    const MerrowFreeformViewport viewport = [self viewport];
    return CGPointMake((viewPoint.x - viewport.offsetX) / viewport.scale, (viewPoint.y - viewport.offsetY) / viewport.scale);
}

- (CGPoint)viewPointForContentPoint:(CGPoint)contentPoint viewport:(MerrowFreeformViewport)viewport {
    return CGPointMake(contentPoint.x * viewport.scale + viewport.offsetX,
                       contentPoint.y * viewport.scale + viewport.offsetY);
}

- (NSRect)viewRectForContentRect:(NSRect)contentRect viewport:(MerrowFreeformViewport)viewport {
    CGPoint origin = [self viewPointForContentPoint:contentRect.origin viewport:viewport];
    return NSMakeRect(origin.x,
                      origin.y,
                      contentRect.size.width * viewport.scale,
                      contentRect.size.height * viewport.scale);
}

- (NSRect)frameForNode:(MerrowFreeformNodeRecord *)node {
    return NSMakeRect(node.x - node.width / 2.0, node.y - node.height / 2.0, node.width, node.height);
}

- (NSRect)frameForSubgraph:(MerrowFreeformSubgraphRecord *)subgraph {
    return NSMakeRect(subgraph.x, subgraph.y, subgraph.width, subgraph.height);
}

- (NSRect)selectedObjectFrame {
    if (self.selectedSubgraph) {
        return [self frameForSubgraph:self.selectedSubgraph];
    }
    if (self.selectedNode) {
        return [self frameForNode:self.selectedNode];
    }
    return NSZeroRect;
}

- (CGFloat)selectedObjectWidth {
    if (self.selectedSubgraph) return self.selectedSubgraph.width;
    if (self.selectedNode) return self.selectedNode.width;
    return 0.0;
}

- (CGFloat)selectedObjectHeight {
    if (self.selectedSubgraph) return self.selectedSubgraph.height;
    if (self.selectedNode) return self.selectedNode.height;
    return 0.0;
}

- (BOOL)nodeShapeUsesLockedAspectRatio:(uint32_t)shape {
    return shape == 3;
}

- (CGSize)minimumSizeForNodeShape:(uint32_t)shape {
    switch (shape) {
        case 2:
            return CGSizeMake(84.0, 64.0);
        case 3:
            return CGSizeMake(64.0, 64.0);
        case 4:
            return CGSizeMake(100.0, 64.0);
        case 5:
        case 6:
            return CGSizeMake(104.0, 64.0);
        case 7:
        case 8:
        case 9:
        case 10:
        case 11:
            return CGSizeMake(108.0, 60.0);
        default:
            return CGSizeMake(88.0, 52.0);
    }
}

- (BOOL)parentChainFromSubgraphId:(NSString *)subgraphId containsAncestorId:(NSString *)ancestorId {
    NSString *parentId = subgraphId;
    while (parentId.length > 0) {
        if ([parentId isEqualToString:ancestorId]) {
            return YES;
        }
        parentId = self.subgraphsById[parentId].parentSubgraphId;
    }
    return NO;
}

- (NSRect)descendantBoundsForSubgraph:(MerrowFreeformSubgraphRecord *)subgraph found:(BOOL *)found {
    BOOL hasBounds = NO;
    NSRect bounds = NSZeroRect;
    NSString *subgraphId = subgraph.subgraphId ?: @"";

    for (MerrowFreeformNodeRecord *node in self.nodes) {
        if (![self parentChainFromSubgraphId:node.parentSubgraphId containsAncestorId:subgraphId]) continue;
        NSRect frame = [self frameForNode:node];
        bounds = hasBounds ? NSUnionRect(bounds, frame) : frame;
        hasBounds = YES;
    }

    for (MerrowFreeformSubgraphRecord *child in self.subgraphs) {
        if (child == subgraph) continue;
        if (![self parentChainFromSubgraphId:child.parentSubgraphId containsAncestorId:subgraphId]) continue;
        NSRect frame = [self frameForSubgraph:child];
        bounds = hasBounds ? NSUnionRect(bounds, frame) : frame;
        hasBounds = YES;
    }

    if (found) {
        *found = hasBounds;
    }
    return bounds;
}

- (MerrowFreeformInsets)minimumInsetsForSubgraph:(MerrowFreeformSubgraphRecord *)subgraph {
    const CGFloat topInset = MAX(34.0, subgraph.titleFontSize + 20.0);
    return (MerrowFreeformInsets){ .left = 18.0, .top = topInset, .right = 18.0, .bottom = 18.0 };
}

- (NSRect)clampedFrameForNodeRect:(NSRect)rect shape:(uint32_t)shape {
    CGSize minimum = [self minimumSizeForNodeShape:shape];
    rect.size.width = MAX(rect.size.width, minimum.width);
    rect.size.height = MAX(rect.size.height, minimum.height);

    if ([self nodeShapeUsesLockedAspectRatio:shape]) {
        const CGFloat side = MAX(MAX(rect.size.width, rect.size.height), minimum.width);
        rect.size.width = side;
        rect.size.height = side;
    }

    if (NSMaxX(rect) > self.documentWidth) {
        rect.origin.x = MAX(0.0, self.documentWidth - rect.size.width);
    }
    if (NSMaxY(rect) > self.documentHeight) {
        rect.origin.y = MAX(0.0, self.documentHeight - rect.size.height);
    }
    rect.origin.x = MAX(0.0, rect.origin.x);
    rect.origin.y = MAX(0.0, rect.origin.y);
    return rect;
}

- (NSRect)clampedFrameForSubgraphRect:(NSRect)rect subgraph:(MerrowFreeformSubgraphRecord *)subgraph {
    MerrowFreeformInsets insets = [self minimumInsetsForSubgraph:subgraph];
    rect.size.width = MAX(rect.size.width, 180.0);
    rect.size.height = MAX(rect.size.height, 120.0);

    BOOL hasDescendants = NO;
    NSRect bounds = [self descendantBoundsForSubgraph:subgraph found:&hasDescendants];
    if (hasDescendants) {
        rect.origin.x = MIN(rect.origin.x, NSMinX(bounds) - insets.left);
        rect.origin.y = MIN(rect.origin.y, NSMinY(bounds) - insets.top);
        rect.size.width = MAX(rect.size.width, NSMaxX(bounds) + insets.right - rect.origin.x);
        rect.size.height = MAX(rect.size.height, NSMaxY(bounds) + insets.bottom - rect.origin.y);
    }

    if (NSMaxX(rect) > self.documentWidth) {
        rect.origin.x = MAX(0.0, self.documentWidth - rect.size.width);
    }
    if (NSMaxY(rect) > self.documentHeight) {
        rect.origin.y = MAX(0.0, self.documentHeight - rect.size.height);
    }
    rect.origin.x = MAX(0.0, rect.origin.x);
    rect.origin.y = MAX(0.0, rect.origin.y);
    rect.size.width = MIN(rect.size.width, self.documentWidth - rect.origin.x);
    rect.size.height = MIN(rect.size.height, self.documentHeight - rect.origin.y);
    rect.size.width = MAX(rect.size.width, 180.0);
    rect.size.height = MAX(rect.size.height, 120.0);
    return rect;
}

- (CGFloat)selectionHandleSizeForViewport:(MerrowFreeformViewport)viewport {
    return MAX(10.0 / MAX(viewport.scale, 0.01), 6.0);
}

- (CGPoint)centerForResizeHandle:(MerrowFreeformResizeHandle)handle inRect:(NSRect)rect {
    switch (handle) {
        case MerrowFreeformResizeHandleNorthWest:
            return CGPointMake(NSMinX(rect), NSMinY(rect));
        case MerrowFreeformResizeHandleNorth:
            return CGPointMake(NSMidX(rect), NSMinY(rect));
        case MerrowFreeformResizeHandleNorthEast:
            return CGPointMake(NSMaxX(rect), NSMinY(rect));
        case MerrowFreeformResizeHandleEast:
            return CGPointMake(NSMaxX(rect), NSMidY(rect));
        case MerrowFreeformResizeHandleSouthEast:
            return CGPointMake(NSMaxX(rect), NSMaxY(rect));
        case MerrowFreeformResizeHandleSouth:
            return CGPointMake(NSMidX(rect), NSMaxY(rect));
        case MerrowFreeformResizeHandleSouthWest:
            return CGPointMake(NSMinX(rect), NSMaxY(rect));
        case MerrowFreeformResizeHandleWest:
            return CGPointMake(NSMinX(rect), NSMidY(rect));
        default:
            return CGPointZero;
    }
}

- (NSRect)rectForResizeHandle:(MerrowFreeformResizeHandle)handle inRect:(NSRect)rect viewport:(MerrowFreeformViewport)viewport {
    const CGFloat size = [self selectionHandleSizeForViewport:viewport];
    CGPoint center = [self centerForResizeHandle:handle inRect:rect];
    return NSMakeRect(center.x - size / 2.0, center.y - size / 2.0, size, size);
}

- (MerrowFreeformResizeHandle)resizeHandleAtContentPoint:(CGPoint)point {
    if (!self.selectedNode && !self.selectedSubgraph) return MerrowFreeformResizeHandleNone;
    NSRect rect = [self selectedObjectFrame];
    MerrowFreeformViewport viewport = [self viewport];
    static const MerrowFreeformResizeHandle handles[] = {
        MerrowFreeformResizeHandleNorthWest,
        MerrowFreeformResizeHandleNorth,
        MerrowFreeformResizeHandleNorthEast,
        MerrowFreeformResizeHandleEast,
        MerrowFreeformResizeHandleSouthEast,
        MerrowFreeformResizeHandleSouth,
        MerrowFreeformResizeHandleSouthWest,
        MerrowFreeformResizeHandleWest,
    };
    for (NSUInteger idx = 0; idx < sizeof(handles) / sizeof(handles[0]); idx += 1) {
        if (NSPointInRect(point, [self rectForResizeHandle:handles[idx] inRect:rect viewport:viewport])) {
            return handles[idx];
        }
    }
    return MerrowFreeformResizeHandleNone;
}

- (void)drawResizeHandlesForRect:(NSRect)rect viewport:(MerrowFreeformViewport)viewport {
    static const MerrowFreeformResizeHandle handles[] = {
        MerrowFreeformResizeHandleNorthWest,
        MerrowFreeformResizeHandleNorth,
        MerrowFreeformResizeHandleNorthEast,
        MerrowFreeformResizeHandleEast,
        MerrowFreeformResizeHandleSouthEast,
        MerrowFreeformResizeHandleSouth,
        MerrowFreeformResizeHandleSouthWest,
        MerrowFreeformResizeHandleWest,
    };
    [[NSColor whiteColor] setFill];
    [[NSColor colorWithCalibratedRed:0.20 green:0.56 blue:0.96 alpha:1.0] setStroke];
    for (NSUInteger idx = 0; idx < sizeof(handles) / sizeof(handles[0]); idx += 1) {
        NSRect handleRect = [self rectForResizeHandle:handles[idx] inRect:rect viewport:viewport];
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:handleRect xRadius:2.0 yRadius:2.0];
        path.lineWidth = MAX(1.0 / MAX(viewport.scale, 0.01), 0.75);
        [path fill];
        [path stroke];
    }
}

- (NSRect)rectByShiftingInsideDocument:(NSRect)rect {
    if (NSMinX(rect) < 0.0) rect.origin.x = 0.0;
    if (NSMinY(rect) < 0.0) rect.origin.y = 0.0;
    if (NSMaxX(rect) > self.documentWidth) rect.origin.x = MAX(0.0, self.documentWidth - rect.size.width);
    if (NSMaxY(rect) > self.documentHeight) rect.origin.y = MAX(0.0, self.documentHeight - rect.size.height);
    return rect;
}

- (NSRect)lockedAspectRectFromInitialFrame:(NSRect)initialFrame handle:(MerrowFreeformResizeHandle)handle currentPoint:(CGPoint)currentPoint minimumSide:(CGFloat)minimumSide {
    const CGFloat clampedX = MAX(0.0, MIN(currentPoint.x, self.documentWidth));
    const CGFloat clampedY = MAX(0.0, MIN(currentPoint.y, self.documentHeight));
    CGPoint anchor = CGPointZero;
    CGFloat side = minimumSide;

    switch (handle) {
        case MerrowFreeformResizeHandleNorthWest:
            anchor = CGPointMake(NSMaxX(initialFrame), NSMaxY(initialFrame));
            side = MAX(MAX(anchor.x - clampedX, anchor.y - clampedY), minimumSide);
            return [self rectByShiftingInsideDocument:NSMakeRect(anchor.x - side, anchor.y - side, side, side)];
        case MerrowFreeformResizeHandleNorth:
            anchor = CGPointMake(NSMidX(initialFrame), NSMaxY(initialFrame));
            side = MAX(anchor.y - clampedY, minimumSide);
            return [self rectByShiftingInsideDocument:NSMakeRect(anchor.x - side / 2.0, anchor.y - side, side, side)];
        case MerrowFreeformResizeHandleNorthEast:
            anchor = CGPointMake(NSMinX(initialFrame), NSMaxY(initialFrame));
            side = MAX(MAX(clampedX - anchor.x, anchor.y - clampedY), minimumSide);
            return [self rectByShiftingInsideDocument:NSMakeRect(anchor.x, anchor.y - side, side, side)];
        case MerrowFreeformResizeHandleEast:
            anchor = CGPointMake(NSMinX(initialFrame), NSMidY(initialFrame));
            side = MAX(clampedX - anchor.x, minimumSide);
            return [self rectByShiftingInsideDocument:NSMakeRect(anchor.x, anchor.y - side / 2.0, side, side)];
        case MerrowFreeformResizeHandleSouthEast:
            anchor = CGPointMake(NSMinX(initialFrame), NSMinY(initialFrame));
            side = MAX(MAX(clampedX - anchor.x, clampedY - anchor.y), minimumSide);
            return [self rectByShiftingInsideDocument:NSMakeRect(anchor.x, anchor.y, side, side)];
        case MerrowFreeformResizeHandleSouth:
            anchor = CGPointMake(NSMidX(initialFrame), NSMinY(initialFrame));
            side = MAX(clampedY - anchor.y, minimumSide);
            return [self rectByShiftingInsideDocument:NSMakeRect(anchor.x - side / 2.0, anchor.y, side, side)];
        case MerrowFreeformResizeHandleSouthWest:
            anchor = CGPointMake(NSMaxX(initialFrame), NSMinY(initialFrame));
            side = MAX(MAX(anchor.x - clampedX, clampedY - anchor.y), minimumSide);
            return [self rectByShiftingInsideDocument:NSMakeRect(anchor.x - side, anchor.y, side, side)];
        case MerrowFreeformResizeHandleWest:
            anchor = CGPointMake(NSMaxX(initialFrame), NSMidY(initialFrame));
            side = MAX(anchor.x - clampedX, minimumSide);
            return [self rectByShiftingInsideDocument:NSMakeRect(anchor.x - side, anchor.y - side / 2.0, side, side)];
        default:
            return initialFrame;
    }
}

- (NSRect)resizedRectFromInitialFrame:(NSRect)initialFrame handle:(MerrowFreeformResizeHandle)handle currentPoint:(CGPoint)currentPoint minimumSize:(CGSize)minimumSize lockAspectRatio:(BOOL)lockAspectRatio {
    if (lockAspectRatio) {
        return [self lockedAspectRectFromInitialFrame:initialFrame handle:handle currentPoint:currentPoint minimumSide:MAX(minimumSize.width, minimumSize.height)];
    }

    CGFloat left = NSMinX(initialFrame);
    CGFloat top = NSMinY(initialFrame);
    CGFloat right = NSMaxX(initialFrame);
    CGFloat bottom = NSMaxY(initialFrame);
    const CGFloat clampedX = MAX(0.0, MIN(currentPoint.x, self.documentWidth));
    const CGFloat clampedY = MAX(0.0, MIN(currentPoint.y, self.documentHeight));

    switch (handle) {
        case MerrowFreeformResizeHandleNorthWest:
            left = MIN(clampedX, right - minimumSize.width);
            top = MIN(clampedY, bottom - minimumSize.height);
            break;
        case MerrowFreeformResizeHandleNorth:
            top = MIN(clampedY, bottom - minimumSize.height);
            break;
        case MerrowFreeformResizeHandleNorthEast:
            right = MAX(clampedX, left + minimumSize.width);
            top = MIN(clampedY, bottom - minimumSize.height);
            break;
        case MerrowFreeformResizeHandleEast:
            right = MAX(clampedX, left + minimumSize.width);
            break;
        case MerrowFreeformResizeHandleSouthEast:
            right = MAX(clampedX, left + minimumSize.width);
            bottom = MAX(clampedY, top + minimumSize.height);
            break;
        case MerrowFreeformResizeHandleSouth:
            bottom = MAX(clampedY, top + minimumSize.height);
            break;
        case MerrowFreeformResizeHandleSouthWest:
            left = MIN(clampedX, right - minimumSize.width);
            bottom = MAX(clampedY, top + minimumSize.height);
            break;
        case MerrowFreeformResizeHandleWest:
            left = MIN(clampedX, right - minimumSize.width);
            break;
        default:
            break;
    }

    return NSMakeRect(left, top, right - left, bottom - top);
}

- (void)applyFrame:(NSRect)frame toNode:(MerrowFreeformNodeRecord *)node {
    node.x = NSMidX(frame);
    node.y = NSMidY(frame);
    node.width = frame.size.width;
    node.height = frame.size.height;
}

- (void)applyFrame:(NSRect)frame toSubgraph:(MerrowFreeformSubgraphRecord *)subgraph previousFrame:(NSRect)previousFrame {
    const CGFloat dx = frame.origin.x - previousFrame.origin.x;
    const CGFloat dy = frame.origin.y - previousFrame.origin.y;
    subgraph.x = frame.origin.x;
    subgraph.y = frame.origin.y;
    subgraph.width = frame.size.width;
    subgraph.height = frame.size.height;
    subgraph.titleX += dx;
    subgraph.titleY += dy;
}

- (void)updateSelectedObjectWidth:(CGFloat)width {
    NSData *undoSnapshot = [self snapshotDataForUndo];
    if (self.selectedNode) {
        NSRect frame = [self frameForNode:self.selectedNode];
        frame.size.width = width;
        if ([self nodeShapeUsesLockedAspectRatio:self.selectedNode.shape]) {
            frame.size.height = width;
        }
        frame = [self clampedFrameForNodeRect:frame shape:self.selectedNode.shape];
        [self applyFrame:frame toNode:self.selectedNode];
    } else if (self.selectedSubgraph) {
        NSRect previousFrame = [self frameForSubgraph:self.selectedSubgraph];
        NSRect frame = previousFrame;
        frame.size.width = width;
        frame = [self clampedFrameForSubgraphRect:frame subgraph:self.selectedSubgraph];
        [self applyFrame:frame toSubgraph:self.selectedSubgraph previousFrame:previousFrame];
    } else {
        return;
    }
    [self registerUndoSnapshot:undoSnapshot actionName:@"Resize Object"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)updateSelectedObjectHeight:(CGFloat)height {
    NSData *undoSnapshot = [self snapshotDataForUndo];
    if (self.selectedNode) {
        NSRect frame = [self frameForNode:self.selectedNode];
        frame.size.height = height;
        if ([self nodeShapeUsesLockedAspectRatio:self.selectedNode.shape]) {
            frame.size.width = height;
        }
        frame = [self clampedFrameForNodeRect:frame shape:self.selectedNode.shape];
        [self applyFrame:frame toNode:self.selectedNode];
    } else if (self.selectedSubgraph) {
        NSRect previousFrame = [self frameForSubgraph:self.selectedSubgraph];
        NSRect frame = previousFrame;
        frame.size.height = height;
        frame = [self clampedFrameForSubgraphRect:frame subgraph:self.selectedSubgraph];
        [self applyFrame:frame toSubgraph:self.selectedSubgraph previousFrame:previousFrame];
    } else {
        return;
    }
    [self registerUndoSnapshot:undoSnapshot actionName:@"Resize Object"];
    [self notifySelectionChanged];
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (NSBezierPath *)pathForNode:(MerrowFreeformNodeRecord *)node {
    const CGFloat x = node.x - node.width / 2.0;
    const CGFloat y = node.y - node.height / 2.0;
    const CGFloat w = node.width;
    const CGFloat h = node.height;
    const CGFloat cx = node.x;
    const CGFloat cy = node.y;
    const CGFloat hw = w / 2.0;
    const CGFloat hh = h / 2.0;

    switch (node.shape) {
        case 0:
            return [NSBezierPath bezierPathWithRect:NSMakeRect(x, y, w, h)];
        case 1:
            return [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, y, w, h) xRadius:MIN(MIN(hw, hh), 12.0) yRadius:MIN(MIN(hw, hh), 12.0)];
        case 2: {
            CGPoint points[4] = {
                { cx, cy - hh },
                { cx + hw, cy },
                { cx, cy + hh },
                { cx - hw, cy },
            };
            return MerrowFreeformPolygonPath(points, 4);
        }
        case 3:
            return [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x, y, w, h)];
        case 4: {
            const CGFloat inset = hw * 0.35;
            CGPoint points[6] = {
                { cx - hw + inset, cy - hh },
                { cx + hw - inset, cy - hh },
                { cx + hw, cy },
                { cx + hw - inset, cy + hh },
                { cx - hw + inset, cy + hh },
                { cx - hw, cy },
            };
            return MerrowFreeformPolygonPath(points, 6);
        }
        case 5:
        case 6:
            return [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, y, w, h) xRadius:hh yRadius:hh];
        case 7: {
            const CGFloat inset = hw * 0.25;
            CGPoint points[4] = {
                { cx - hw + inset, cy - hh },
                { cx + hw - inset, cy - hh },
                { cx + hw, cy + hh },
                { cx - hw, cy + hh },
            };
            return MerrowFreeformPolygonPath(points, 4);
        }
        case 8: {
            const CGFloat inset = hw * 0.25;
            CGPoint points[4] = {
                { cx - hw, cy - hh },
                { cx + hw, cy - hh },
                { cx + hw - inset, cy + hh },
                { cx - hw + inset, cy + hh },
            };
            return MerrowFreeformPolygonPath(points, 4);
        }
        case 9: {
            const CGFloat slant = hw * 0.25;
            CGPoint points[4] = {
                { cx - hw + slant, cy - hh },
                { cx + hw + slant, cy - hh },
                { cx + hw - slant, cy + hh },
                { cx - hw - slant, cy + hh },
            };
            return MerrowFreeformPolygonPath(points, 4);
        }
        case 10: {
            const CGFloat slant = hw * 0.25;
            CGPoint points[4] = {
                { cx - hw - slant, cy - hh },
                { cx + hw - slant, cy - hh },
                { cx + hw + slant, cy + hh },
                { cx - hw + slant, cy + hh },
            };
            return MerrowFreeformPolygonPath(points, 4);
        }
        case 11:
            return [NSBezierPath bezierPathWithRect:NSMakeRect(x, y, w, h)];
        default:
            return [NSBezierPath bezierPathWithRect:NSMakeRect(x, y, w, h)];
    }
}

- (NSRect)textRectForNode:(MerrowFreeformNodeRecord *)node {
    const CGFloat outerX = node.x - node.width / 2.0;
    const CGFloat outerY = node.y - node.height / 2.0;
    CGFloat insetX = 10.0;
    CGFloat insetY = 8.0;

    switch (node.shape) {
        case 2:
            insetX = MAX(18.0, node.width * 0.24);
            insetY = MAX(12.0, node.height * 0.20);
            break;
        case 3:
            insetX = MAX(16.0, node.width * 0.18);
            insetY = MAX(12.0, node.height * 0.18);
            break;
        case 4:
            insetX = MAX(18.0, node.width * 0.18);
            break;
        case 5:
            insetX = 12.0;
            insetY = MAX(14.0, node.height * 0.22);
            break;
        case 6:
            insetX = MAX(16.0, node.height * 0.28);
            break;
        case 7:
        case 8:
        case 9:
        case 10:
        case 11:
            insetX = MAX(16.0, node.width * 0.16);
            break;
        default:
            break;
    }

    const CGFloat maxWidth = MAX(node.width - insetX * 2.0, 24.0);
    const CGFloat maxHeight = MAX(node.height - insetY * 2.0, 18.0);
    return NSMakeRect(outerX + insetX, outerY + insetY, maxWidth, maxHeight);
}

- (void)drawCenteredText:(NSString *)text inRect:(NSRect)rect fontSize:(CGFloat)fontSize color:(NSColor *)color {
    if (text.length == 0) return;
    NSFont *font = [NSFont fontWithName:@"Lato" size:fontSize] ?: [NSFont systemFontOfSize:fontSize weight:NSFontWeightRegular];
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSDictionary *attrs = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: style };
    [text drawWithRect:rect options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:attrs];
}

- (void)drawText:(NSString *)text inRect:(NSRect)rect fontSize:(CGFloat)fontSize color:(NSColor *)color alignment:(NSTextAlignment)alignment {
    if (text.length == 0) return;
    NSFont *font = [NSFont fontWithName:@"Lato" size:fontSize] ?: [NSFont systemFontOfSize:fontSize weight:NSFontWeightRegular];
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = alignment;
    NSDictionary *attrs = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: color ?: [NSColor blackColor], NSParagraphStyleAttributeName: style };
    [text drawWithRect:rect options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:attrs];
}

- (BOOL)isClassNode:(MerrowFreeformNodeRecord *)node {
    return self.graphType == MerrowFreeformGraphTypeClass && node != nil;
}

- (NSRect)classHeaderRectForNode:(MerrowFreeformNodeRecord *)node {
    const CGFloat x = node.x - node.width / 2.0;
    const CGFloat y = node.y - node.height / 2.0;
    const CGFloat headerHeight = MIN(node.height, MerrowFreeformClassHeaderHeight(node.label, node.subtitle, node.labelFontSize));
    return NSMakeRect(x, y, node.width, headerHeight);
}

- (void)drawClassNode:(MerrowFreeformNodeRecord *)node {
    const CGFloat x = node.x - node.width / 2.0;
    const CGFloat y = node.y - node.height / 2.0;
    const CGFloat w = node.width;
    const CGFloat h = node.height;
    const CGFloat dividerWidth = MAX(node.strokeWidth, 1.0);
    const CGFloat inset = 12.0;
    const CGFloat sectionGap = 8.0;
    const CGFloat lineHeight = 17.0;
    const CGFloat headerHeight = MIN(h, MerrowFreeformClassHeaderHeight(node.label, node.subtitle, node.labelFontSize));
    const CGFloat bodyHeight = MAX(0.0, h - headerHeight);
    const NSUInteger attributeLines = MerrowFreeformLineCount(node.attributesText);
    const NSUInteger methodLines = MerrowFreeformLineCount(node.methodsText);
    CGFloat attributesHeight = attributeLines > 0 ? attributeLines * lineHeight + 14.0 : 0.0;
    if (attributesHeight > bodyHeight) attributesHeight = bodyHeight;
    CGFloat methodsHeight = MAX(0.0, bodyHeight - attributesHeight);

    NSColor *bodyFillColor = node.bodyFillColor ?: node.fillColor ?: [NSColor whiteColor];
    [bodyFillColor setFill];
    NSRectFill(NSMakeRect(x, y, w, h));
    NSColor *headerFillColor = node.fillColor ?: [NSColor whiteColor];
    [headerFillColor setFill];
    NSRectFill(NSMakeRect(x, y, w, headerHeight));

    NSBezierPath *outline = [NSBezierPath bezierPathWithRect:NSMakeRect(x, y, w, h)];
    outline.lineWidth = node.strokeWidth;
    [node.strokeColor setStroke];
    [outline stroke];

    NSBezierPath *headerDivider = [NSBezierPath bezierPath];
    [headerDivider moveToPoint:CGPointMake(x, y + headerHeight)];
    [headerDivider lineToPoint:CGPointMake(x + w, y + headerHeight)];
    headerDivider.lineWidth = dividerWidth;
    [headerDivider stroke];

    if (attributeLines > 0 && methodLines > 0) {
        NSBezierPath *bodyDivider = [NSBezierPath bezierPath];
        [bodyDivider moveToPoint:CGPointMake(x, y + headerHeight + attributesHeight)];
        [bodyDivider lineToPoint:CGPointMake(x + w, y + headerHeight + attributesHeight)];
        bodyDivider.lineWidth = dividerWidth;
        [bodyDivider stroke];
    }

    CGFloat subtitleHeight = MerrowFreeformLineCount(node.subtitle) > 0 ? MerrowFreeformLineCount(node.subtitle) * 14.0 + 2.0 : 0.0;
    CGFloat headerTextY = y + 10.0;
    if (subtitleHeight > 0.0) {
        [self drawText:node.subtitle inRect:NSMakeRect(x + inset, headerTextY, w - inset * 2.0, subtitleHeight) fontSize:12.0 color:node.labelColor alignment:NSTextAlignmentCenter];
        headerTextY += subtitleHeight + 2.0;
    }
    [self drawText:node.label inRect:NSMakeRect(x + inset, headerTextY, w - inset * 2.0, MAX(20.0, headerHeight - (headerTextY - y) - 8.0)) fontSize:MAX(node.labelFontSize, 15.0) color:node.labelColor alignment:NSTextAlignmentCenter];

    if (attributeLines > 0) {
        [self drawText:node.attributesText inRect:NSMakeRect(x + inset, y + headerHeight + sectionGap, w - inset * 2.0, MAX(0.0, attributesHeight - sectionGap)) fontSize:12.0 color:[NSColor colorWithCalibratedRed:0.19 green:0.22 blue:0.27 alpha:1.0] alignment:NSTextAlignmentLeft];
    }
    if (methodLines > 0) {
        const CGFloat methodsY = y + headerHeight + (attributeLines > 0 ? attributesHeight : 0.0) + sectionGap;
        [self drawText:node.methodsText inRect:NSMakeRect(x + inset, methodsY, w - inset * 2.0, MAX(0.0, methodsHeight - sectionGap)) fontSize:12.0 color:[NSColor colorWithCalibratedRed:0.19 green:0.22 blue:0.27 alpha:1.0] alignment:NSTextAlignmentLeft];
    }
}

- (void)drawEdgeEndpointStyle:(uint32_t)style from:(CGPoint)from tip:(CGPoint)tip color:(NSColor *)color {
    if (style == 0) return;
    const CGFloat dx = tip.x - from.x;
    const CGFloat dy = tip.y - from.y;
    const CGFloat len = hypot(dx, dy);
    if (len < 0.001) return;

    const CGFloat ux = dx / len;
    const CGFloat uy = dy / len;
    const CGFloat px = -uy;
    const CGFloat py = ux;

    if (style == 1 || style == 4) {
        const CGFloat size = style == 1 ? 13.0 : 11.0;
        const CGFloat halfWidth = size * 0.48;
        CGPoint points[3] = {
            tip,
            { tip.x - ux * size + px * halfWidth, tip.y - uy * size + py * halfWidth },
            { tip.x - ux * size - px * halfWidth, tip.y - uy * size - py * halfWidth },
        };
        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:points[0]];
        [path lineToPoint:points[1]];
        [path lineToPoint:points[2]];
        [path closePath];
        path.lineWidth = 1.6;
        [[NSColor whiteColor] setFill];
        [path fill];
        [color setStroke];
        [path stroke];
        return;
    }

    if (style == 2 || style == 3) {
        const CGFloat size = 12.0;
        const CGFloat halfWidth = size * 0.42;
        CGPoint points[4] = {
            tip,
            { tip.x - ux * (size * 0.5) + px * halfWidth, tip.y - uy * (size * 0.5) + py * halfWidth },
            { tip.x - ux * size, tip.y - uy * size },
            { tip.x - ux * (size * 0.5) - px * halfWidth, tip.y - uy * (size * 0.5) - py * halfWidth },
        };
        NSBezierPath *path = MerrowFreeformPolygonPath(points, 4);
        path.lineWidth = 1.6;
        [(style == 2 ? color : [NSColor whiteColor]) setFill];
        [path fill];
        [color setStroke];
        [path stroke];
        return;
    }

    if (style == 5) {
        const CGFloat radius = 6.0;
        CGPoint center = CGPointMake(tip.x - ux * radius, tip.y - uy * radius);
        NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - radius, center.y - radius, radius * 2.0, radius * 2.0)];
        path.lineWidth = 1.6;
        [[NSColor whiteColor] setFill];
        [path fill];
        [color setStroke];
        [path stroke];
    }
}

- (NSString *)svgElementForEdgeEndpointStyle:(uint32_t)style from:(CGPoint)from tip:(CGPoint)tip color:(NSColor *)color {
    if (style == 0) return @"";
    const CGFloat dx = tip.x - from.x;
    const CGFloat dy = tip.y - from.y;
    const CGFloat len = hypot(dx, dy);
    if (len < 0.001) return @"";

    const CGFloat ux = dx / len;
    const CGFloat uy = dy / len;
    const CGFloat px = -uy;
    const CGFloat py = ux;
    NSString *strokeAttrs = MerrowFreeformSVGPaintAttributes(@"stroke", color);

    if (style == 1 || style == 4) {
        const CGFloat size = style == 1 ? 13.0 : 11.0;
        const CGFloat halfWidth = size * 0.48;
        CGPoint points[3] = {
            tip,
            { tip.x - ux * size + px * halfWidth, tip.y - uy * size + py * halfWidth },
            { tip.x - ux * size - px * halfWidth, tip.y - uy * size - py * halfWidth },
        };
        return [NSString stringWithFormat:@"<polygon points=\"%@\" fill=\"#FFFFFF\" %@ stroke-width=\"1.6\" />", MerrowFreeformPointList(points, 3), strokeAttrs];
    }

    if (style == 2 || style == 3) {
        const CGFloat size = 12.0;
        const CGFloat halfWidth = size * 0.42;
        CGPoint points[4] = {
            tip,
            { tip.x - ux * (size * 0.5) + px * halfWidth, tip.y - uy * (size * 0.5) + py * halfWidth },
            { tip.x - ux * size, tip.y - uy * size },
            { tip.x - ux * (size * 0.5) - px * halfWidth, tip.y - uy * (size * 0.5) - py * halfWidth },
        };
        NSString *fillAttrs = style == 2 ? MerrowFreeformSVGPaintAttributes(@"fill", color) : @"fill=\"#FFFFFF\"";
        return [NSString stringWithFormat:@"<polygon points=\"%@\" %@ %@ stroke-width=\"1.6\" />", MerrowFreeformPointList(points, 4), fillAttrs, strokeAttrs];
    }

    if (style == 5) {
        const CGFloat radius = 6.0;
        CGPoint center = CGPointMake(tip.x - ux * radius, tip.y - uy * radius);
        return [NSString stringWithFormat:@"<circle cx=\"%.2f\" cy=\"%.2f\" r=\"%.2f\" fill=\"#FFFFFF\" %@ stroke-width=\"1.6\" />", center.x, center.y, radius, strokeAttrs];
    }

    return @"";
}

- (CGPoint)clipPointFromNode:(MerrowFreeformNodeRecord *)node toward:(CGPoint)toward {
    const CGFloat dx = toward.x - node.x;
    const CGFloat dy = toward.y - node.y;
    if (fabs(dx) < 0.001 && fabs(dy) < 0.001) {
        return CGPointMake(node.x, node.y);
    }
    const CGFloat hw = MAX(node.width / 2.0, 1.0);
    const CGFloat hh = MAX(node.height / 2.0, 1.0);
    const CGFloat scale = 1.0 / MAX(fabs(dx) / hw, fabs(dy) / hh);
    return CGPointMake(node.x + dx * scale, node.y + dy * scale);
}

- (CGPoint)centerForSubgraph:(MerrowFreeformSubgraphRecord *)subgraph {
    return CGPointMake(subgraph.x + subgraph.width / 2.0, subgraph.y + subgraph.height / 2.0);
}

- (CGPoint)clipPointFromSubgraph:(MerrowFreeformSubgraphRecord *)subgraph toward:(CGPoint)toward {
    CGPoint center = [self centerForSubgraph:subgraph];
    const CGFloat dx = toward.x - center.x;
    const CGFloat dy = toward.y - center.y;
    if (fabs(dx) < 0.001 && fabs(dy) < 0.001) {
        return center;
    }
    const CGFloat hw = MAX(subgraph.width / 2.0, 1.0);
    const CGFloat hh = MAX(subgraph.height / 2.0, 1.0);
    const CGFloat scale = 1.0 / MAX(fabs(dx) / hw, fabs(dy) / hh);
    return CGPointMake(center.x + dx * scale, center.y + dy * scale);
}

- (BOOL)resolveEdge:(MerrowFreeformEdgeRecord *)edge start:(CGPoint *)start end:(CGPoint *)end {
    MerrowFreeformNodeRecord *sourceNode = self.nodesById[edge.sourceId];
    MerrowFreeformSubgraphRecord *sourceSubgraph = self.subgraphsById[edge.sourceId];
    MerrowFreeformNodeRecord *targetNode = self.nodesById[edge.targetId];
    MerrowFreeformSubgraphRecord *targetSubgraph = self.subgraphsById[edge.targetId];
    if ((!sourceNode && !sourceSubgraph) || (!targetNode && !targetSubgraph)) return NO;

    CGPoint sourceCenter = sourceNode ? CGPointMake(sourceNode.x, sourceNode.y) : [self centerForSubgraph:sourceSubgraph];
    CGPoint targetCenter = targetNode ? CGPointMake(targetNode.x, targetNode.y) : [self centerForSubgraph:targetSubgraph];

    if (start) {
        *start = sourceNode ? [self clipPointFromNode:sourceNode toward:targetCenter] : [self clipPointFromSubgraph:sourceSubgraph toward:targetCenter];
    }
    if (end) {
        *end = targetNode ? [self clipPointFromNode:targetNode toward:sourceCenter] : [self clipPointFromSubgraph:targetSubgraph toward:sourceCenter];
    }
    return YES;
}

- (MerrowFreeformNodeRecord *)nodeAtContentPoint:(CGPoint)point {
    for (MerrowFreeformNodeRecord *node in [self.nodes reverseObjectEnumerator]) {
        if ([self isInvisibleAnchorNode:node]) continue;
        NSRect rect = NSMakeRect(node.x - node.width / 2.0, node.y - node.height / 2.0, node.width, node.height);
        if (NSPointInRect(point, rect)) {
            return node;
        }
    }
    return nil;
}

- (BOOL)subgraph:(MerrowFreeformSubgraphRecord *)subgraph containsContentPoint:(CGPoint)point {
    return NSPointInRect(point, NSMakeRect(subgraph.x, subgraph.y, subgraph.width, subgraph.height));
}

- (BOOL)isPointOnSubgraphChrome:(CGPoint)point subgraph:(MerrowFreeformSubgraphRecord *)subgraph {
    NSRect frame = NSMakeRect(subgraph.x, subgraph.y, subgraph.width, subgraph.height);
    if (!NSPointInRect(point, frame)) return NO;

    const CGFloat borderThickness = MAX(10.0, subgraph.strokeWidth + 6.0);
    NSRect inner = NSInsetRect(frame, borderThickness, borderThickness);
    const CGFloat titleBandHeight = MAX(28.0, subgraph.titleFontSize + 16.0);
    if (point.y <= NSMinY(frame) + titleBandHeight) return YES;
    return !NSPointInRect(point, inner);
}

- (MerrowFreeformSubgraphRecord *)subgraphAtContentPoint:(CGPoint)point preferContainingRegion:(BOOL)preferContainingRegion {
    for (MerrowFreeformSubgraphRecord *subgraph in [self.subgraphs reverseObjectEnumerator]) {
        if (![self subgraph:subgraph containsContentPoint:point]) continue;
        if (preferContainingRegion || [self isPointOnSubgraphChrome:point subgraph:subgraph]) {
            return subgraph;
        }
    }
    return nil;
}

- (CGFloat)distanceFromPoint:(CGPoint)point toSegmentStart:(CGPoint)start end:(CGPoint)end {
    const CGFloat dx = end.x - start.x;
    const CGFloat dy = end.y - start.y;
    const CGFloat len_sq = dx * dx + dy * dy;
    if (len_sq < 0.001) {
        return hypot(point.x - start.x, point.y - start.y);
    }
    const CGFloat t = MAX(0.0, MIN(1.0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / len_sq));
    const CGFloat proj_x = start.x + t * dx;
    const CGFloat proj_y = start.y + t * dy;
    return hypot(point.x - proj_x, point.y - proj_y);
}

- (MerrowFreeformEdgeRecord *)edgeAtContentPoint:(CGPoint)point {
    CGFloat bestDistance = 14.0;
    MerrowFreeformEdgeRecord *bestEdge = nil;
    for (MerrowFreeformEdgeRecord *edge in self.edges) {
        CGPoint start = CGPointZero;
        CGPoint end = CGPointZero;
        if (![self resolveEdge:edge start:&start end:&end]) continue;
        const CGFloat distance = [self distanceFromPoint:point toSegmentStart:start end:end];
        if (distance <= bestDistance) {
            bestDistance = distance;
            bestEdge = edge;
        }
    }

    return bestEdge;
}

- (CGFloat)edgeEndpointHandleRadiusForViewport:(MerrowFreeformViewport)viewport {
    return MAX(8.0 / MAX(viewport.scale, 0.01), 5.0);
}

- (NSRect)edgeEndpointHandleRectAtPoint:(CGPoint)point viewport:(MerrowFreeformViewport)viewport {
    const CGFloat radius = [self edgeEndpointHandleRadiusForViewport:viewport];
    return NSMakeRect(point.x - radius, point.y - radius, radius * 2.0, radius * 2.0);
}

- (MerrowFreeformEdgeEndpointHandle)edgeEndpointHandleAtContentPoint:(CGPoint)point {
    if (!self.selectedEdge) return MerrowFreeformEdgeEndpointHandleNone;
    CGPoint start = CGPointZero;
    CGPoint end = CGPointZero;
    if (![self resolveEdge:self.selectedEdge start:&start end:&end]) {
        return MerrowFreeformEdgeEndpointHandleNone;
    }

    MerrowFreeformViewport viewport = [self viewport];
    if (NSPointInRect(point, [self edgeEndpointHandleRectAtPoint:start viewport:viewport])) {
        return MerrowFreeformEdgeEndpointHandleSource;
    }
    if (NSPointInRect(point, [self edgeEndpointHandleRectAtPoint:end viewport:viewport])) {
        return MerrowFreeformEdgeEndpointHandleTarget;
    }
    return MerrowFreeformEdgeEndpointHandleNone;
}

- (NSString *)connectableObjectIdAtContentPoint:(CGPoint)point {
    MerrowFreeformNodeRecord *node = [self nodeAtContentPoint:point];
    if (node.nodeId.length > 0) {
        return node.nodeId;
    }

    MerrowFreeformSubgraphRecord *subgraph = [self subgraphAtContentPoint:point preferContainingRegion:YES];
    if (subgraph.subgraphId.length > 0) {
        return subgraph.subgraphId;
    }

    return nil;
}

- (CGPoint)centerForObjectId:(NSString *)objectId {
    MerrowFreeformNodeRecord *node = self.nodesById[objectId];
    if (node) {
        return CGPointMake(node.x, node.y);
    }
    MerrowFreeformSubgraphRecord *subgraph = self.subgraphsById[objectId];
    if (subgraph) {
        return [self centerForSubgraph:subgraph];
    }
    return CGPointZero;
}

- (CGPoint)previewPointForDraggingEdgeEndpoint {
    if (!self.draggingEdgeEndpoint || !self.selectedEdge) {
        return CGPointZero;
    }
    if (self.edgeDragHoverObjectId.length > 0) {
        NSString *fixedObjectId = self.activeEdgeEndpointHandle == MerrowFreeformEdgeEndpointHandleSource ? self.selectedEdge.targetId : self.selectedEdge.sourceId;
        CGPoint fixedCenter = [self centerForObjectId:fixedObjectId];
        if (self.activeEdgeEndpointHandle == MerrowFreeformEdgeEndpointHandleSource) {
            MerrowFreeformNodeRecord *node = self.nodesById[self.edgeDragHoverObjectId];
            MerrowFreeformSubgraphRecord *subgraph = self.subgraphsById[self.edgeDragHoverObjectId];
            if (node) return [self clipPointFromNode:node toward:fixedCenter];
            if (subgraph) return [self clipPointFromSubgraph:subgraph toward:fixedCenter];
        } else {
            MerrowFreeformNodeRecord *node = self.nodesById[self.edgeDragHoverObjectId];
            MerrowFreeformSubgraphRecord *subgraph = self.subgraphsById[self.edgeDragHoverObjectId];
            if (node) return [self clipPointFromNode:node toward:fixedCenter];
            if (subgraph) return [self clipPointFromSubgraph:subgraph toward:fixedCenter];
        }
    }
    return self.edgeDragPreviewPoint;
}

- (void)drawEdgeEndpointHandlesForEdge:(MerrowFreeformEdgeRecord *)edge start:(CGPoint)start end:(CGPoint)end viewport:(MerrowFreeformViewport)viewport {
    if (edge != self.selectedEdge) return;
    NSRect sourceRect = [self edgeEndpointHandleRectAtPoint:start viewport:viewport];
    NSRect targetRect = [self edgeEndpointHandleRectAtPoint:end viewport:viewport];
    [[NSColor whiteColor] setFill];
    [[NSColor colorWithCalibratedRed:0.20 green:0.56 blue:0.96 alpha:1.0] setStroke];
    for (NSValue *value in @[ [NSValue valueWithRect:sourceRect], [NSValue valueWithRect:targetRect] ]) {
        NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:value.rectValue];
        path.lineWidth = MAX(1.0 / MAX(viewport.scale, 0.01), 0.75);
        [path fill];
        [path stroke];
    }
}

- (void)drawDraggingEdgePreviewWithViewport:(MerrowFreeformViewport)viewport {
    if (!self.draggingEdgeEndpoint || !self.selectedEdge) return;

    CGPoint start = CGPointZero;
    CGPoint end = CGPointZero;
    if (![self resolveEdge:self.selectedEdge start:&start end:&end]) return;

    CGPoint previewPoint = [self previewPointForDraggingEdgeEndpoint];
    CGPoint fixedPoint = self.activeEdgeEndpointHandle == MerrowFreeformEdgeEndpointHandleSource ? end : start;
    CGPoint dragPoint = self.activeEdgeEndpointHandle == MerrowFreeformEdgeEndpointHandleSource ? start : end;
    dragPoint = previewPoint;

    NSBezierPath *previewPath = [NSBezierPath bezierPath];
    if (self.activeEdgeEndpointHandle == MerrowFreeformEdgeEndpointHandleSource) {
        [previewPath moveToPoint:dragPoint];
        [previewPath lineToPoint:fixedPoint];
    } else {
        [previewPath moveToPoint:fixedPoint];
        [previewPath lineToPoint:dragPoint];
    }
    previewPath.lineJoinStyle = NSLineJoinStyleRound;
    previewPath.lineCapStyle = NSLineCapStyleRound;
    previewPath.lineWidth = MAX(self.selectedEdge.thickness, 1.0);
    CGFloat pattern[2] = { 6.0, 4.0 };
    [previewPath setLineDash:pattern count:2 phase:0.0];
    [[self.selectedEdge.strokeColor colorWithAlphaComponent:0.75] setStroke];
    [previewPath stroke];

    [self drawEdgeEndpointHandlesForEdge:self.selectedEdge
                                  start:self.activeEdgeEndpointHandle == MerrowFreeformEdgeEndpointHandleSource ? dragPoint : start
                                    end:self.activeEdgeEndpointHandle == MerrowFreeformEdgeEndpointHandleTarget ? dragPoint : end
                               viewport:viewport];
}

- (NSDictionary *)serializedNodeDictionary:(MerrowFreeformNodeRecord *)node {
    CGFloat red = 0;
    CGFloat green = 0;
    CGFloat blue = 0;
    CGFloat alpha = 0;
    [[node.fillColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] getRed:&red green:&green blue:&blue alpha:&alpha];
    CGFloat bodyRed = 0;
    CGFloat bodyGreen = 0;
    CGFloat bodyBlue = 0;
    CGFloat bodyAlpha = 0;
    [[(node.bodyFillColor ?: node.fillColor) colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] getRed:&bodyRed green:&bodyGreen blue:&bodyBlue alpha:&bodyAlpha];
    CGFloat strokeRed = 0;
    CGFloat strokeGreen = 0;
    CGFloat strokeBlue = 0;
    CGFloat strokeAlpha = 0;
    [[node.strokeColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] getRed:&strokeRed green:&strokeGreen blue:&strokeBlue alpha:&strokeAlpha];
    CGFloat labelRed = 0;
    CGFloat labelGreen = 0;
    CGFloat labelBlue = 0;
    CGFloat labelAlpha = 0;
    [[node.labelColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] getRed:&labelRed green:&labelGreen blue:&labelBlue alpha:&labelAlpha];

    return @{
        @"id": node.nodeId ?: @"",
        @"label": node.label ?: @"",
        @"subtitle": node.subtitle ?: @"",
        @"attributesText": node.attributesText ?: @"",
        @"methodsText": node.methodsText ?: @"",
        @"parentSubgraphId": node.parentSubgraphId ?: @"",
        @"shape": @(node.shape),
        @"x": @(node.x),
        @"y": @(node.y),
        @"width": @(node.width),
        @"height": @(node.height),
        @"fill": @{ @"r": @(red), @"g": @(green), @"b": @(blue), @"a": @(alpha) },
        @"bodyFill": @{ @"r": @(bodyRed), @"g": @(bodyGreen), @"b": @(bodyBlue), @"a": @(bodyAlpha) },
        @"stroke": @{ @"r": @(strokeRed), @"g": @(strokeGreen), @"b": @(strokeBlue), @"a": @(strokeAlpha) },
        @"strokeWidth": @(node.strokeWidth),
        @"labelColor": @{ @"r": @(labelRed), @"g": @(labelGreen), @"b": @(labelBlue), @"a": @(labelAlpha) },
        @"labelFontSize": @(node.labelFontSize),
    };
}

- (void)drawDocumentInCurrentContextWithViewport:(MerrowFreeformViewport)viewport includeEditorChrome:(BOOL)includeEditorChrome {
    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:viewport.offsetX yBy:viewport.offsetY];
    [transform scaleBy:viewport.scale];
    [transform concat];

    [self.canvasBackgroundColor setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, self.documentWidth, self.documentHeight));

    for (MerrowFreeformSubgraphRecord *subgraph in self.subgraphs) {
        NSRect frame = NSMakeRect(subgraph.x, subgraph.y, subgraph.width, subgraph.height);
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:frame xRadius:subgraph.cornerRadius yRadius:subgraph.cornerRadius];
        [subgraph.fillColor setFill];
        [subgraph.strokeColor setStroke];
        path.lineWidth = subgraph.strokeWidth;
        [path fill];
        [path stroke];

        if (includeEditorChrome && subgraph == self.selectedSubgraph) {
            NSBezierPath *selectionPath = [path copy];
            selectionPath.lineWidth = MAX(subgraph.strokeWidth + 2.0, 3.0);
            CGFloat pattern[2] = { 8.0, 5.0 };
            [selectionPath setLineDash:pattern count:2 phase:0.0];
            [[NSColor colorWithCalibratedRed:0.20 green:0.56 blue:0.96 alpha:1.0] setStroke];
            [selectionPath stroke];
            [self drawResizeHandlesForRect:frame viewport:viewport];
        }

        if (subgraph.title.length > 0) {
            CGFloat titleX = subgraph.titleX > 0.0 ? subgraph.titleX : (subgraph.x + subgraph.cornerRadius + 6.0);
            CGFloat titleY = subgraph.titleY > 0.0 ? subgraph.titleY : (subgraph.y + 16.0);
            NSFont *titleFont = [NSFont fontWithName:@"Lato" size:subgraph.titleFontSize] ?: [NSFont systemFontOfSize:subgraph.titleFontSize weight:NSFontWeightRegular];
            NSDictionary *attrs = @{
                NSFontAttributeName: titleFont,
                NSForegroundColorAttributeName: subgraph.titleColor ?: [NSColor colorWithCalibratedRed:0.24 green:0.26 blue:0.30 alpha:1.0],
            };
            [subgraph.title drawAtPoint:CGPointMake(titleX, titleY - subgraph.titleFontSize * 0.5) withAttributes:attrs];
        }
    }

    for (MerrowFreeformEdgeRecord *edge in self.edges) {
        CGPoint start = CGPointZero;
        CGPoint end = CGPointZero;
        if (![self resolveEdge:edge start:&start end:&end]) continue;

        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:start];
        [path lineToPoint:end];
        path.lineJoinStyle = NSLineJoinStyleRound;
        path.lineCapStyle = NSLineCapStyleRound;
        path.lineWidth = edge.thickness;

        CGFloat pattern[2] = { 0.0, 0.0 };
        if (edge.lineStyle == 1) {
            pattern[0] = 10.0;
            pattern[1] = 6.0;
            [path setLineDash:pattern count:2 phase:0.0];
        } else if (edge.lineStyle == 2) {
            pattern[0] = 4.0;
            pattern[1] = 4.0;
            [path setLineDash:pattern count:2 phase:0.0];
        }

        [edge.strokeColor setStroke];
        [path stroke];

        if (includeEditorChrome && edge == self.selectedEdge) {
            NSBezierPath *selectionPath = [path copy];
            selectionPath.lineWidth = MAX(edge.thickness + 3.0, 4.0);
            CGFloat selectionPattern[2] = { 8.0, 5.0 };
            [selectionPath setLineDash:selectionPattern count:2 phase:0.0];
            [[NSColor colorWithCalibratedRed:0.20 green:0.56 blue:0.96 alpha:0.9] setStroke];
            [selectionPath stroke];
            [self drawEdgeEndpointHandlesForEdge:edge start:start end:end viewport:viewport];
        }

        if (self.graphType == MerrowFreeformGraphTypeClass) {
            [self drawEdgeEndpointStyle:edge.targetEndStyle from:start tip:end color:edge.strokeColor];
            [self drawEdgeEndpointStyle:edge.sourceEndStyle from:end tip:start color:edge.strokeColor];
        } else if (edge.hasArrow) {
            MerrowFreeformDrawArrow(start, end, edge.strokeColor);
        }
        if (self.graphType != MerrowFreeformGraphTypeClass && edge.hasSourceArrow) {
            MerrowFreeformDrawArrow(end, start, edge.strokeColor);
        }

        if (edge.label.length > 0) {
            NSRect labelRect = NSMakeRect((start.x + end.x) * 0.5 - 54.0, (start.y + end.y) * 0.5 - 12.0, 108.0, 24.0);
            [[NSColor colorWithCalibratedWhite:1.0 alpha:0.92] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:labelRect xRadius:4.0 yRadius:4.0] fill];
            [self drawCenteredText:edge.label inRect:labelRect fontSize:12.0 color:[NSColor colorWithCalibratedRed:0.24 green:0.26 blue:0.30 alpha:1.0]];
        }
    }

    for (MerrowFreeformNodeRecord *node in self.nodes) {
        if ([self isInvisibleAnchorNode:node]) continue;
        NSBezierPath *path = nil;
        if ([self isClassNode:node]) {
            path = [NSBezierPath bezierPathWithRect:[self frameForNode:node]];
            [self drawClassNode:node];
        } else {
            path = [self pathForNode:node];
            [node.fillColor setFill];
            [node.strokeColor setStroke];
            path.lineWidth = node.strokeWidth;
            [path fill];
            [path stroke];
        }

        if (includeEditorChrome && node == self.selectedNode) {
            NSBezierPath *selectionPath = [path copy];
            selectionPath.lineWidth = MAX(node.strokeWidth + 2.0, 3.0);
            CGFloat pattern[2] = { 8.0, 5.0 };
            [selectionPath setLineDash:pattern count:2 phase:0.0];
            [[NSColor colorWithCalibratedRed:0.20 green:0.56 blue:0.96 alpha:1.0] setStroke];
            [selectionPath stroke];
            [self drawResizeHandlesForRect:[self frameForNode:node] viewport:viewport];
        }

        if (![self isClassNode:node] && node.shape == 11) {
            const CGFloat hw = node.width / 2.0;
            const CGFloat hh = node.height / 2.0;
            const CGFloat inset = MAX(hw * 0.15, 6.0);
            NSBezierPath *left = [NSBezierPath bezierPath];
            [left moveToPoint:CGPointMake(node.x - hw + inset, node.y - hh)];
            [left lineToPoint:CGPointMake(node.x - hw + inset, node.y + hh)];
            left.lineWidth = node.strokeWidth;
            [left stroke];
            NSBezierPath *right = [NSBezierPath bezierPath];
            [right moveToPoint:CGPointMake(node.x + hw - inset, node.y - hh)];
            [right lineToPoint:CGPointMake(node.x + hw - inset, node.y + hh)];
            right.lineWidth = node.strokeWidth;
            [right stroke];
        }

        if (![self isClassNode:node]) {
            [self drawCenteredText:node.label inRect:[self textRectForNode:node] fontSize:node.labelFontSize color:node.labelColor];
        }
    }

    if (includeEditorChrome) {
        [self drawDraggingEdgePreviewWithViewport:viewport];
    }

    [NSGraphicsContext restoreGraphicsState];
}

- (NSString *)svgTextElementForText:(NSString *)text
                                  x:(CGFloat)x
                                  y:(CGFloat)y
                            fontSize:(CGFloat)fontSize
                               color:(NSColor *)color
                           anchorMid:(BOOL)anchorMid {
    if (text.length == 0) return @"";
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSMutableString *svg = [NSMutableString stringWithFormat:@"<text x=\"%.2f\" y=\"%.2f\" font-family=\"Lato, -apple-system, BlinkMacSystemFont, sans-serif\" font-size=\"%.2f\" %@ %@ text-anchor=\"%@\">",
                           x,
                           y,
                           fontSize,
                           MerrowFreeformSVGPaintAttributes(@"fill", color),
                           anchorMid ? @"dominant-baseline=\"middle\"" : @"dominant-baseline=\"alphabetic\"",
                           anchorMid ? @"middle" : @"start"];
    if (lines.count <= 1) {
        [svg appendString:MerrowFreeformEscapeXML(text)];
    } else {
        CGFloat startY = y - ((CGFloat)(lines.count - 1) * fontSize * 0.6);
        for (NSUInteger idx = 0; idx < lines.count; idx += 1) {
            [svg appendFormat:@"<tspan x=\"%.2f\" y=\"%.2f\">%@</tspan>", x, startY + idx * fontSize * 1.2, MerrowFreeformEscapeXML(lines[idx])];
        }
    }
    [svg appendString:@"</text>"];
    return svg;
}

- (NSString *)svgElementForNode:(MerrowFreeformNodeRecord *)node {
    if ([self isClassNode:node]) {
        const CGFloat x = node.x - node.width / 2.0;
        const CGFloat y = node.y - node.height / 2.0;
        const CGFloat w = node.width;
        const CGFloat h = node.height;
        const CGFloat headerHeight = MIN(h, MerrowFreeformClassHeaderHeight(node.label, node.subtitle, node.labelFontSize));
        const CGFloat bodyHeight = MAX(0.0, h - headerHeight);
        const NSUInteger attributeLines = MerrowFreeformLineCount(node.attributesText);
        const NSUInteger methodLines = MerrowFreeformLineCount(node.methodsText);
        CGFloat attributesHeight = attributeLines > 0 ? attributeLines * 17.0 + 14.0 : 0.0;
        if (attributesHeight > bodyHeight) attributesHeight = bodyHeight;
        NSMutableString *svg = [NSMutableString string];
        [svg appendFormat:@"<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" %@ />", x, y, w, h, MerrowFreeformSVGPaintAttributes(@"fill", node.bodyFillColor ?: node.fillColor)];
        [svg appendFormat:@"<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" %@ />", x, y, w, headerHeight, MerrowFreeformSVGPaintAttributes(@"fill", node.fillColor)];
        [svg appendFormat:@"<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" fill=\"none\" %@ stroke-width=\"%.2f\" />", x, y, w, h, MerrowFreeformSVGPaintAttributes(@"stroke", node.strokeColor), node.strokeWidth];
        [svg appendFormat:@"<line x1=\"%.2f\" y1=\"%.2f\" x2=\"%.2f\" y2=\"%.2f\" %@ stroke-width=\"%.2f\" />", x, y + headerHeight, x + w, y + headerHeight, MerrowFreeformSVGPaintAttributes(@"stroke", node.strokeColor), MAX(node.strokeWidth, 1.0)];
        if (attributeLines > 0 && methodLines > 0) {
            [svg appendFormat:@"<line x1=\"%.2f\" y1=\"%.2f\" x2=\"%.2f\" y2=\"%.2f\" %@ stroke-width=\"%.2f\" />", x, y + headerHeight + attributesHeight, x + w, y + headerHeight + attributesHeight, MerrowFreeformSVGPaintAttributes(@"stroke", node.strokeColor), MAX(node.strokeWidth, 1.0)];
        }
        CGFloat titleY = y + (node.subtitle.length > 0 ? 30.0 : 22.0);
        if (node.subtitle.length > 0) {
            [svg appendString:[self svgTextElementForText:node.subtitle x:node.x y:y + 16.0 fontSize:12.0 color:node.labelColor anchorMid:YES]];
        }
        [svg appendString:[self svgTextElementForText:node.label x:node.x y:titleY fontSize:MAX(node.labelFontSize, 15.0) color:node.labelColor anchorMid:YES]];
        if (attributeLines > 0) {
            [svg appendString:[self svgTextElementForText:node.attributesText x:x + 12.0 y:y + headerHeight + 18.0 fontSize:12.0 color:[NSColor colorWithCalibratedRed:0.19 green:0.22 blue:0.27 alpha:1.0] anchorMid:NO]];
        }
        if (methodLines > 0) {
            [svg appendString:[self svgTextElementForText:node.methodsText x:x + 12.0 y:y + headerHeight + (attributeLines > 0 ? attributesHeight : 0.0) + 18.0 fontSize:12.0 color:[NSColor colorWithCalibratedRed:0.19 green:0.22 blue:0.27 alpha:1.0] anchorMid:NO]];
        }
        return svg;
    }

    const CGFloat x = node.x - node.width / 2.0;
    const CGFloat y = node.y - node.height / 2.0;
    const CGFloat w = node.width;
    const CGFloat h = node.height;
    const CGFloat cx = node.x;
    const CGFloat cy = node.y;
    const CGFloat hw = w / 2.0;
    const CGFloat hh = h / 2.0;
    NSMutableString *svg = [NSMutableString string];
    NSString *fillAttrs = MerrowFreeformSVGPaintAttributes(@"fill", node.fillColor);
    NSString *strokeAttrs = MerrowFreeformSVGPaintAttributes(@"stroke", node.strokeColor);

    switch (node.shape) {
        case 1:
            [svg appendFormat:@"<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" rx=\"%.2f\" ry=\"%.2f\" %@ %@ stroke-width=\"%.2f\" />", x, y, w, h, MIN(MIN(hw, hh), 12.0), MIN(MIN(hw, hh), 12.0), fillAttrs, strokeAttrs, node.strokeWidth];
            break;
        case 2: {
            CGPoint points[4] = { { cx, cy - hh }, { cx + hw, cy }, { cx, cy + hh }, { cx - hw, cy } };
            [svg appendFormat:@"<polygon points=\"%@\" %@ %@ stroke-width=\"%.2f\" />", MerrowFreeformPointList(points, 4), fillAttrs, strokeAttrs, node.strokeWidth];
            break;
        }
        case 3:
            [svg appendFormat:@"<ellipse cx=\"%.2f\" cy=\"%.2f\" rx=\"%.2f\" ry=\"%.2f\" %@ %@ stroke-width=\"%.2f\" />", cx, cy, hw, hh, fillAttrs, strokeAttrs, node.strokeWidth];
            break;
        case 4: {
            const CGFloat inset = hw * 0.35;
            CGPoint points[6] = { { cx - hw + inset, cy - hh }, { cx + hw - inset, cy - hh }, { cx + hw, cy }, { cx + hw - inset, cy + hh }, { cx - hw + inset, cy + hh }, { cx - hw, cy } };
            [svg appendFormat:@"<polygon points=\"%@\" %@ %@ stroke-width=\"%.2f\" />", MerrowFreeformPointList(points, 6), fillAttrs, strokeAttrs, node.strokeWidth];
            break;
        }
        case 5:
        case 6:
            [svg appendFormat:@"<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" rx=\"%.2f\" ry=\"%.2f\" %@ %@ stroke-width=\"%.2f\" />", x, y, w, h, hh, hh, fillAttrs, strokeAttrs, node.strokeWidth];
            break;
        case 7: {
            const CGFloat inset = hw * 0.25;
            CGPoint points[4] = { { cx - hw + inset, cy - hh }, { cx + hw - inset, cy - hh }, { cx + hw, cy + hh }, { cx - hw, cy + hh } };
            [svg appendFormat:@"<polygon points=\"%@\" %@ %@ stroke-width=\"%.2f\" />", MerrowFreeformPointList(points, 4), fillAttrs, strokeAttrs, node.strokeWidth];
            break;
        }
        case 8: {
            const CGFloat inset = hw * 0.25;
            CGPoint points[4] = { { cx - hw, cy - hh }, { cx + hw, cy - hh }, { cx + hw - inset, cy + hh }, { cx - hw + inset, cy + hh } };
            [svg appendFormat:@"<polygon points=\"%@\" %@ %@ stroke-width=\"%.2f\" />", MerrowFreeformPointList(points, 4), fillAttrs, strokeAttrs, node.strokeWidth];
            break;
        }
        case 9: {
            const CGFloat slant = hw * 0.25;
            CGPoint points[4] = { { cx - hw + slant, cy - hh }, { cx + hw + slant, cy - hh }, { cx + hw - slant, cy + hh }, { cx - hw - slant, cy + hh } };
            [svg appendFormat:@"<polygon points=\"%@\" %@ %@ stroke-width=\"%.2f\" />", MerrowFreeformPointList(points, 4), fillAttrs, strokeAttrs, node.strokeWidth];
            break;
        }
        case 10: {
            const CGFloat slant = hw * 0.25;
            CGPoint points[4] = { { cx - hw - slant, cy - hh }, { cx + hw - slant, cy - hh }, { cx + hw + slant, cy + hh }, { cx - hw + slant, cy + hh } };
            [svg appendFormat:@"<polygon points=\"%@\" %@ %@ stroke-width=\"%.2f\" />", MerrowFreeformPointList(points, 4), fillAttrs, strokeAttrs, node.strokeWidth];
            break;
        }
        case 11:
            [svg appendFormat:@"<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" %@ %@ stroke-width=\"%.2f\" />", x, y, w, h, fillAttrs, strokeAttrs, node.strokeWidth];
            break;
        default:
            [svg appendFormat:@"<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" %@ %@ stroke-width=\"%.2f\" />", x, y, w, h, fillAttrs, strokeAttrs, node.strokeWidth];
            break;
    }

    if (node.shape == 11) {
        const CGFloat inset = MAX(hw * 0.15, 6.0);
        [svg appendFormat:@"<line x1=\"%.2f\" y1=\"%.2f\" x2=\"%.2f\" y2=\"%.2f\" %@ stroke-width=\"%.2f\" />", node.x - hw + inset, node.y - hh, node.x - hw + inset, node.y + hh, strokeAttrs, node.strokeWidth];
        [svg appendFormat:@"<line x1=\"%.2f\" y1=\"%.2f\" x2=\"%.2f\" y2=\"%.2f\" %@ stroke-width=\"%.2f\" />", node.x + hw - inset, node.y - hh, node.x + hw - inset, node.y + hh, strokeAttrs, node.strokeWidth];
    }

    [svg appendString:[self svgTextElementForText:node.label x:node.x y:node.y fontSize:node.labelFontSize color:node.labelColor anchorMid:YES]];
    return svg;
}

- (BOOL)writePNGExportToPath:(NSString *)path scale:(CGFloat)scale error:(NSError **)error {
    NSInteger pixelsWide = (NSInteger)ceil(MAX(self.documentWidth * MAX(scale, 1.0), 1.0));
    NSInteger pixelsHigh = (NSInteger)ceil(MAX(self.documentHeight * MAX(scale, 1.0), 1.0));
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                     pixelsWide:pixelsWide
                                                                     pixelsHigh:pixelsHigh
                                                                  bitsPerSample:8
                                                                samplesPerPixel:4
                                                                       hasAlpha:YES
                                                                       isPlanar:NO
                                                                 colorSpaceName:NSCalibratedRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    if (!rep) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: @"Unable to create a bitmap for the freeform PNG export." }];
        }
        return NO;
    }

    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    context.shouldAntialias = YES;
    [[NSColor clearColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, pixelsWide, pixelsHigh));
    [self drawDocumentInCurrentContextWithViewport:(MerrowFreeformViewport){ .scale = MAX(scale, 1.0), .offsetX = 0.0, .offsetY = 0.0 } includeEditorChrome:NO];
    [context flushGraphics];
    [NSGraphicsContext restoreGraphicsState];

    NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (!pngData) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: @"Unable to encode the freeform PNG export." }];
        }
        return NO;
    }
    return [pngData writeToFile:path options:NSDataWritingAtomic error:error];
}

- (BOOL)writeSVGExportToPath:(NSString *)path scale:(CGFloat)scale error:(NSError **)error {
    NSMutableString *svg = [NSMutableString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%.0f\" height=\"%.0f\" viewBox=\"0 0 %.2f %.2f\">\n",
                           ceil(self.documentWidth * MAX(scale, 1.0)),
                           ceil(self.documentHeight * MAX(scale, 1.0)),
                           self.documentWidth,
                           self.documentHeight];
    [svg appendFormat:@"<rect x=\"0\" y=\"0\" width=\"%.2f\" height=\"%.2f\" %@ />\n", self.documentWidth, self.documentHeight, MerrowFreeformSVGPaintAttributes(@"fill", self.canvasBackgroundColor)];

    for (MerrowFreeformSubgraphRecord *subgraph in self.subgraphs) {
        CGFloat titleX = subgraph.titleX > 0.0 ? subgraph.titleX : (subgraph.x + subgraph.cornerRadius + 6.0);
        CGFloat titleY = subgraph.titleY > 0.0 ? subgraph.titleY : (subgraph.y + 16.0);
        [svg appendFormat:@"<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" rx=\"%.2f\" ry=\"%.2f\" %@ %@ stroke-width=\"%.2f\" />\n",
         subgraph.x,
         subgraph.y,
         subgraph.width,
         subgraph.height,
         subgraph.cornerRadius,
         subgraph.cornerRadius,
         MerrowFreeformSVGPaintAttributes(@"fill", subgraph.fillColor),
         MerrowFreeformSVGPaintAttributes(@"stroke", subgraph.strokeColor),
         subgraph.strokeWidth];
        [svg appendString:[self svgTextElementForText:subgraph.title x:titleX y:titleY fontSize:subgraph.titleFontSize color:subgraph.titleColor anchorMid:NO]];
        [svg appendString:@"\n"];
    }

    for (MerrowFreeformEdgeRecord *edge in self.edges) {
        CGPoint start = CGPointZero;
        CGPoint end = CGPointZero;
        if (![self resolveEdge:edge start:&start end:&end]) continue;

        NSMutableString *line = [NSMutableString stringWithFormat:@"<line x1=\"%.2f\" y1=\"%.2f\" x2=\"%.2f\" y2=\"%.2f\" %@ stroke-width=\"%.2f\" stroke-linecap=\"round\" stroke-linejoin=\"round\" fill=\"none\"",
                                  start.x,
                                  start.y,
                                  end.x,
                                  end.y,
                                  MerrowFreeformSVGPaintAttributes(@"stroke", edge.strokeColor),
                                  edge.thickness];
        if (edge.lineStyle == 1) {
            [line appendString:@" stroke-dasharray=\"10 6\""];
        } else if (edge.lineStyle == 2) {
            [line appendString:@" stroke-dasharray=\"4 4\""];
        }
        [line appendString:@" />\n"];
        [svg appendString:line];

        if (self.graphType == MerrowFreeformGraphTypeClass) {
            [svg appendString:[self svgElementForEdgeEndpointStyle:edge.targetEndStyle from:start tip:end color:edge.strokeColor]];
            [svg appendString:@"\n"];
            [svg appendString:[self svgElementForEdgeEndpointStyle:edge.sourceEndStyle from:end tip:start color:edge.strokeColor]];
            [svg appendString:@"\n"];
        } else {
            if (edge.hasArrow) {
                NSString *points = MerrowFreeformArrowPointList(start, end);
                if (points) {
                    [svg appendFormat:@"<polygon points=\"%@\" %@ />\n", points, MerrowFreeformSVGPaintAttributes(@"fill", edge.strokeColor)];
                }
            }
            if (edge.hasSourceArrow) {
                NSString *points = MerrowFreeformArrowPointList(end, start);
                if (points) {
                    [svg appendFormat:@"<polygon points=\"%@\" %@ />\n", points, MerrowFreeformSVGPaintAttributes(@"fill", edge.strokeColor)];
                }
            }
        }

        if (edge.label.length > 0) {
            NSRect labelRect = NSMakeRect((start.x + end.x) * 0.5 - 54.0, (start.y + end.y) * 0.5 - 12.0, 108.0, 24.0);
            [svg appendFormat:@"<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" rx=\"4\" ry=\"4\" fill=\"#FFFFFF\" fill-opacity=\"0.92\" />\n", labelRect.origin.x, labelRect.origin.y, labelRect.size.width, labelRect.size.height];
            [svg appendString:[self svgTextElementForText:edge.label x:NSMidX(labelRect) y:NSMidY(labelRect) fontSize:12.0 color:[NSColor colorWithCalibratedRed:0.24 green:0.26 blue:0.30 alpha:1.0] anchorMid:YES]];
            [svg appendString:@"\n"];
        }
    }

    for (MerrowFreeformNodeRecord *node in self.nodes) {
        [svg appendString:[self svgElementForNode:node]];
        [svg appendString:@"\n"];
    }

    [svg appendString:@"</svg>\n"];
    NSData *data = [svg dataUsingEncoding:NSUTF8StringEncoding];
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

- (NSDictionary *)serializedEdgeDictionary:(MerrowFreeformEdgeRecord *)edge {
    CGFloat red = 0;
    CGFloat green = 0;
    CGFloat blue = 0;
    CGFloat alpha = 0;
    [[edge.strokeColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] getRed:&red green:&green blue:&blue alpha:&alpha];

    return @{
        @"sourceId": edge.sourceId ?: @"",
        @"targetId": edge.targetId ?: @"",
        @"label": edge.label ?: @"",
        @"color": @{ @"r": @(red), @"g": @(green), @"b": @(blue), @"a": @(alpha) },
        @"thickness": @(edge.thickness),
        @"lineStyle": @(edge.lineStyle),
        @"hasArrow": @(edge.hasArrow),
        @"hasSourceArrow": @(edge.hasSourceArrow),
        @"sourceEndStyle": @(edge.sourceEndStyle),
        @"targetEndStyle": @(edge.targetEndStyle),
    };
}

- (NSDictionary *)serializedSubgraphDictionary:(MerrowFreeformSubgraphRecord *)subgraph {
    CGFloat fillRed = 0;
    CGFloat fillGreen = 0;
    CGFloat fillBlue = 0;
    CGFloat fillAlpha = 0;
    [[subgraph.fillColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] getRed:&fillRed green:&fillGreen blue:&fillBlue alpha:&fillAlpha];

    CGFloat strokeRed = 0;
    CGFloat strokeGreen = 0;
    CGFloat strokeBlue = 0;
    CGFloat strokeAlpha = 0;
    [[subgraph.strokeColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] getRed:&strokeRed green:&strokeGreen blue:&strokeBlue alpha:&strokeAlpha];

    CGFloat titleRed = 0;
    CGFloat titleGreen = 0;
    CGFloat titleBlue = 0;
    CGFloat titleAlpha = 0;
    [[subgraph.titleColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] getRed:&titleRed green:&titleGreen blue:&titleBlue alpha:&titleAlpha];

    return @{
        @"id": subgraph.subgraphId ?: @"",
        @"title": subgraph.title ?: @"",
        @"parentSubgraphId": subgraph.parentSubgraphId ?: @"",
        @"x": @(subgraph.x),
        @"y": @(subgraph.y),
        @"width": @(subgraph.width),
        @"height": @(subgraph.height),
        @"cornerRadius": @(subgraph.cornerRadius),
        @"fill": @{ @"r": @(fillRed), @"g": @(fillGreen), @"b": @(fillBlue), @"a": @(fillAlpha) },
        @"stroke": @{ @"r": @(strokeRed), @"g": @(strokeGreen), @"b": @(strokeBlue), @"a": @(strokeAlpha) },
        @"strokeWidth": @(subgraph.strokeWidth),
        @"titleX": @(subgraph.titleX),
        @"titleY": @(subgraph.titleY),
        @"titleFontSize": @(subgraph.titleFontSize),
        @"titleColor": @{ @"r": @(titleRed), @"g": @(titleGreen), @"b": @(titleBlue), @"a": @(titleAlpha) },
    };
}

- (nullable NSData *)serializedDocumentDataWithError:(NSError **)error {
    CGFloat red = 0;
    CGFloat green = 0;
    CGFloat blue = 0;
    CGFloat alpha = 0;
    [[self.canvasBackgroundColor colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]] getRed:&red green:&green blue:&blue alpha:&alpha];

    NSMutableArray *subgraphDicts = [NSMutableArray arrayWithCapacity:self.subgraphs.count];
    for (MerrowFreeformSubgraphRecord *subgraph in self.subgraphs) {
        [subgraphDicts addObject:[self serializedSubgraphDictionary:subgraph]];
    }

    NSMutableArray *nodeDicts = [NSMutableArray arrayWithCapacity:self.nodes.count];
    for (MerrowFreeformNodeRecord *node in self.nodes) {
        [nodeDicts addObject:[self serializedNodeDictionary:node]];
    }

    NSMutableArray *edgeDicts = [NSMutableArray arrayWithCapacity:self.edges.count];
    for (MerrowFreeformEdgeRecord *edge in self.edges) {
        [edgeDicts addObject:[self serializedEdgeDictionary:edge]];
    }

    NSDictionary *root = @{
        @"format": @"merrow-freeform-ffm-v1",
        @"graphType": @(self.graphType),
        @"width": @(self.documentWidth),
        @"height": @(self.documentHeight),
        @"background": @{ @"r": @(red), @"g": @(green), @"b": @(blue), @"a": @(alpha) },
        @"subgraphs": subgraphDicts,
        @"nodes": nodeDicts,
        @"edges": edgeDicts,
    };

    return [NSPropertyListSerialization dataWithPropertyList:root
                                                      format:NSPropertyListBinaryFormat_v1_0
                                                     options:0
                                                       error:error];
}

- (NSColor *)colorFromDictionary:(NSDictionary *)dict fallback:(NSColor *)fallback {
    if (![dict isKindOfClass:[NSDictionary class]]) return fallback;
    return [NSColor colorWithCalibratedRed:[dict[@"r"] doubleValue]
                                     green:[dict[@"g"] doubleValue]
                                      blue:[dict[@"b"] doubleValue]
                                     alpha:[dict[@"a"] doubleValue]];
}

- (BOOL)loadSerializedDocumentData:(NSData *)data error:(NSError **)error {
    NSError *plistError = nil;
    NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
    id root = [NSPropertyListSerialization propertyListWithData:data
                                                        options:NSPropertyListMutableContainersAndLeaves
                                                         format:&format
                                                          error:&plistError];
    if (!root) {
        root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&plistError];
    }
    if (![root isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileReadCorruptFileError
                                     userInfo:@{ NSLocalizedDescriptionKey: @"The freeform graph file is not a valid FFM document.", NSUnderlyingErrorKey: plistError ?: [NSNull null] }];
        }
        return NO;
    }

    NSDictionary *dict = (NSDictionary *)root;
    NSString *formatName = [[dict[@"format"] description] lowercaseString];
    BOOL supportedFormat = [formatName isEqualToString:@"merrow-freeform-ffm-v1"] || [formatName isEqualToString:@"merrow-freeform-v1"];
    if (!supportedFormat) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownStringEncodingError userInfo:@{ NSLocalizedDescriptionKey: @"Unsupported freeform graph format." }];
        }
        return NO;
    }

    [self clearDocument];
    self.graphType = (MerrowFreeformGraphType)MAX(0, MIN([dict[@"graphType"] integerValue], (NSInteger)MerrowFreeformGraphTypeClass));
    self.canvasBackgroundColor = [self colorFromDictionary:dict[@"background"] fallback:[NSColor whiteColor]];
    self.documentWidth = MAX([dict[@"width"] doubleValue], 600.0);
    self.documentHeight = MAX([dict[@"height"] doubleValue], 400.0);

    NSArray *subgraphs = dict[@"subgraphs"];
    for (NSDictionary *subgraphDict in subgraphs) {
        if (![subgraphDict isKindOfClass:[NSDictionary class]]) continue;
        MerrowFreeformSubgraphRecord *subgraph = [[MerrowFreeformSubgraphRecord alloc] init];
        subgraph.subgraphId = [[subgraphDict[@"id"] description] copy] ?: @"";
        subgraph.title = [[subgraphDict[@"title"] description] copy] ?: @"";
        subgraph.parentSubgraphId = [[subgraphDict[@"parentSubgraphId"] description] copy];
        if ([subgraph.parentSubgraphId isEqualToString:@""]) {
            subgraph.parentSubgraphId = nil;
        }
        subgraph.x = [subgraphDict[@"x"] doubleValue];
        subgraph.y = [subgraphDict[@"y"] doubleValue];
        subgraph.width = MAX([subgraphDict[@"width"] doubleValue], 40.0);
        subgraph.height = MAX([subgraphDict[@"height"] doubleValue], 40.0);
        subgraph.cornerRadius = MAX([subgraphDict[@"cornerRadius"] doubleValue], 0.0);
        subgraph.fillColor = [self colorFromDictionary:subgraphDict[@"fill"] fallback:[NSColor colorWithCalibratedWhite:0.96 alpha:1.0]];
        subgraph.strokeColor = [self colorFromDictionary:subgraphDict[@"stroke"] fallback:[NSColor colorWithCalibratedWhite:0.55 alpha:1.0]];
        subgraph.strokeWidth = MAX([subgraphDict[@"strokeWidth"] doubleValue], 1.0);
        subgraph.titleX = [subgraphDict[@"titleX"] doubleValue];
        subgraph.titleY = [subgraphDict[@"titleY"] doubleValue];
        subgraph.titleFontSize = MAX([subgraphDict[@"titleFontSize"] doubleValue], 8.0);
        subgraph.titleColor = [self colorFromDictionary:subgraphDict[@"titleColor"] fallback:[NSColor colorWithCalibratedRed:0.24 green:0.26 blue:0.30 alpha:1.0]];
        [self.subgraphs addObject:subgraph];
        if (subgraph.subgraphId.length > 0) {
            self.subgraphsById[subgraph.subgraphId] = subgraph;
        }
    }

    NSArray *nodes = dict[@"nodes"];
    for (NSDictionary *nodeDict in nodes) {
        if (![nodeDict isKindOfClass:[NSDictionary class]]) continue;
        MerrowFreeformNodeRecord *node = [[MerrowFreeformNodeRecord alloc] init];
        node.nodeId = [[nodeDict[@"id"] description] copy] ?: @"";
        node.label = [[nodeDict[@"label"] description] copy] ?: @"";
        node.subtitle = [[nodeDict[@"subtitle"] description] copy] ?: @"";
        node.attributesText = [[nodeDict[@"attributesText"] description] copy] ?: @"";
        node.methodsText = [[nodeDict[@"methodsText"] description] copy] ?: @"";
        node.parentSubgraphId = [[nodeDict[@"parentSubgraphId"] description] copy];
        if ([node.parentSubgraphId isEqualToString:@""]) {
            node.parentSubgraphId = nil;
        }
        node.shape = (uint32_t)[nodeDict[@"shape"] integerValue];
        node.x = [nodeDict[@"x"] doubleValue];
        node.y = [nodeDict[@"y"] doubleValue];
        node.width = MAX([nodeDict[@"width"] doubleValue], 20.0);
        node.height = MAX([nodeDict[@"height"] doubleValue], 20.0);
        node.fillColor = [self colorFromDictionary:nodeDict[@"fill"] fallback:[NSColor whiteColor]];
        node.bodyFillColor = [self colorFromDictionary:nodeDict[@"bodyFill"] fallback:node.fillColor];
        node.strokeColor = [self colorFromDictionary:nodeDict[@"stroke"] fallback:[NSColor blackColor]];
        node.strokeWidth = MAX([nodeDict[@"strokeWidth"] doubleValue], 1.0);
        node.labelColor = [self colorFromDictionary:nodeDict[@"labelColor"] fallback:[NSColor blackColor]];
        node.labelFontSize = MAX([nodeDict[@"labelFontSize"] doubleValue], 8.0);
        [self.nodes addObject:node];
        if (node.nodeId.length > 0) {
            self.nodesById[node.nodeId] = node;
        }
    }

    NSArray *edges = dict[@"edges"];
    for (NSDictionary *edgeDict in edges) {
        if (![edgeDict isKindOfClass:[NSDictionary class]]) continue;
        MerrowFreeformEdgeRecord *edge = [[MerrowFreeformEdgeRecord alloc] init];
        edge.sourceId = [[edgeDict[@"sourceId"] description] copy] ?: @"";
        edge.targetId = [[edgeDict[@"targetId"] description] copy] ?: @"";
        edge.label = [[edgeDict[@"label"] description] copy] ?: @"";
        edge.strokeColor = [self colorFromDictionary:edgeDict[@"color"] fallback:[NSColor blackColor]];
        edge.thickness = MAX([edgeDict[@"thickness"] doubleValue], 1.0);
        edge.lineStyle = (uint32_t)MAX(0, MIN([edgeDict[@"lineStyle"] integerValue], 3));
        edge.hasArrow = [edgeDict[@"hasArrow"] boolValue];
        edge.hasSourceArrow = [edgeDict[@"hasSourceArrow"] boolValue];
        edge.sourceEndStyle = (uint32_t)MerrowFreeformClampEndStyle([edgeDict[@"sourceEndStyle"] integerValue]);
        edge.targetEndStyle = (uint32_t)MerrowFreeformClampEndStyle([edgeDict[@"targetEndStyle"] integerValue]);
        if (edge.sourceEndStyle > 0) edge.hasSourceArrow = YES;
        if (edge.targetEndStyle > 0) edge.hasArrow = YES;
        [self.edges addObject:edge];
    }

    [self notifySelectionChanged];
    [self setNeedsDisplay:YES];
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithCalibratedRed:0.93 green:0.94 blue:0.96 alpha:1.0] setFill];
    NSRectFill(self.bounds);

    const MerrowFreeformViewport viewport = [self viewport];
    [self drawDocumentInCurrentContextWithViewport:viewport includeEditorChrome:YES];
}

- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    NSPoint viewPoint = [self convertPoint:event.locationInWindow fromView:nil];
    CGPoint contentPoint = [self contentPointForViewPoint:viewPoint];
    if (self.insertionKind == MerrowFreeformInsertionKindNode) {
        [self placePendingNodeAtContentPoint:contentPoint];
        return;
    }
    if (self.insertionKind == MerrowFreeformInsertionKindSubgraph) {
        [self placePendingSubgraphAtContentPoint:contentPoint];
        return;
    }
    if (self.insertionKind == MerrowFreeformInsertionKindConnector) {
        NSString *targetId = [self connectableObjectIdAtContentPoint:contentPoint];
        if (targetId.length > 0 && ![targetId isEqualToString:self.connectorSourceObjectId]) {
            [self createConnectorFromObjectId:self.connectorSourceObjectId toObjectId:targetId];
        }
        return;
    }

    MerrowFreeformEdgeEndpointHandle edgeHandle = [self edgeEndpointHandleAtContentPoint:contentPoint];
    if (edgeHandle != MerrowFreeformEdgeEndpointHandleNone && self.selectedEdge) {
        [self beginUndoGroupingForAction:@"Reconnect Connector"];
        self.activeEdgeEndpointHandle = edgeHandle;
        self.draggingEdgeEndpoint = YES;
        self.draggingSelection = NO;
        self.resizingSelection = NO;
        self.edgeDragPreviewPoint = contentPoint;
        self.edgeDragOriginalSourceId = [self.selectedEdge.sourceId copy];
        self.edgeDragOriginalTargetId = [self.selectedEdge.targetId copy];
        self.edgeDragHoverObjectId = nil;
        [self setNeedsDisplay:YES];
        return;
    }

    MerrowFreeformResizeHandle resizeHandle = [self resizeHandleAtContentPoint:contentPoint];
    if (resizeHandle != MerrowFreeformResizeHandleNone) {
        [self beginUndoGroupingForAction:@"Resize Object"];
        self.activeResizeHandle = resizeHandle;
        self.resizingSelection = YES;
        self.draggingSelection = NO;
        self.resizeStartContentPoint = contentPoint;
        self.resizeInitialFrame = [self selectedObjectFrame];
        [self setNeedsDisplay:YES];
        return;
    }

    const BOOL shiftSelectsSubgraph = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    MerrowFreeformSubgraphRecord *hitSubgraph = [self subgraphAtContentPoint:contentPoint preferContainingRegion:shiftSelectsSubgraph];
    MerrowFreeformNodeRecord *hitNode = hitSubgraph && shiftSelectsSubgraph ? nil : [self nodeAtContentPoint:contentPoint];
    MerrowFreeformEdgeRecord *hitEdge = (hitNode || hitSubgraph) ? nil : [self edgeAtContentPoint:contentPoint];
    self.selectedSubgraph = hitSubgraph;
    self.selectedNode = hitSubgraph ? nil : hitNode;
    self.selectedEdge = (hitSubgraph || hitNode) ? nil : hitEdge;
    if (hitNode || hitSubgraph) {
        [self beginUndoGroupingForAction:@"Move Object"];
    } else {
        [self discardPendingUndoGroup];
    }
    self.draggingSelection = hitNode != nil || hitSubgraph != nil;
    self.draggingCanvas = !self.draggingSelection && hitEdge == nil;
    self.lastViewDragPoint = viewPoint;
    self.lastDragContentPoint = contentPoint;
    [self notifySelectionChanged];
    [self setNeedsDisplay:YES];
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    if (self.insertionModeActive) {
        return nil;
    }
    CGPoint contentPoint = [self contentPointForViewPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    MerrowFreeformSubgraphRecord *hitSubgraph = [self subgraphAtContentPoint:contentPoint preferContainingRegion:YES];
    MerrowFreeformNodeRecord *hitNode = hitSubgraph ? nil : [self nodeAtContentPoint:contentPoint];
    MerrowFreeformEdgeRecord *hitEdge = (hitNode || hitSubgraph) ? nil : [self edgeAtContentPoint:contentPoint];

    if (hitNode || hitEdge || hitSubgraph) {
        self.selectedSubgraph = hitSubgraph;
        self.selectedNode = hitSubgraph ? nil : hitNode;
        self.selectedEdge = (hitSubgraph || hitNode) ? nil : hitEdge;
        self.draggingSelection = NO;
        [self notifySelectionChanged];
        [self setNeedsDisplay:YES];
    }

    if (!self.selectedNode && !self.selectedEdge && !self.selectedSubgraph) {
        return nil;
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Object"];
    if (self.selectedNode || self.selectedSubgraph) {
        NSMenuItem *connectorItem = [[NSMenuItem alloc] initWithTitle:@"Start Connector" action:@selector(startConnectorFromSelection:) keyEquivalent:@""];
        connectorItem.target = self;
        connectorItem.representedObject = self.selectedConnectableObjectId;
        connectorItem.enabled = self.connectableObjects.count >= 2;
        [menu addItem:connectorItem];
        [menu addItem:[NSMenuItem separatorItem]];
    }
    NSMenuItem *deleteItem = [[NSMenuItem alloc] initWithTitle:@"Delete" action:@selector(deleteSelectedObject:) keyEquivalent:@""];
    deleteItem.target = self;
    [menu addItem:deleteItem];
    return menu;
}

- (void)keyDown:(NSEvent *)event {
    NSString *characters = event.charactersIgnoringModifiers ?: @"";
    unichar first = characters.length > 0 ? [characters characterAtIndex:0] : 0;
    if (event.keyCode == 53 || first == 0x1B) {
        if (self.draggingEdgeEndpoint && self.selectedEdge) {
            self.selectedEdge.sourceId = self.edgeDragOriginalSourceId ?: self.selectedEdge.sourceId;
            self.selectedEdge.targetId = self.edgeDragOriginalTargetId ?: self.selectedEdge.targetId;
            self.draggingEdgeEndpoint = NO;
            self.activeEdgeEndpointHandle = MerrowFreeformEdgeEndpointHandleNone;
            self.edgeDragHoverObjectId = nil;
            [self discardPendingUndoGroup];
            [self setNeedsDisplay:YES];
            return;
        }
        if (self.insertionModeActive) {
            [self cancelInsertionMode];
            return;
        }
    }
    if (event.keyCode == 51 || event.keyCode == 117 || first == NSDeleteCharacter || first == NSBackspaceCharacter || first == NSDeleteFunctionKey) {
        if ([self deleteCurrentSelection]) {
            return;
        }
    }

    [super keyDown:event];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint viewPoint = [self convertPoint:event.locationInWindow fromView:nil];
    CGPoint contentPoint = [self contentPointForViewPoint:viewPoint];
    if (self.draggingEdgeEndpoint && self.selectedEdge) {
        self.edgeDragPreviewPoint = contentPoint;
        self.edgeDragHoverObjectId = [self connectableObjectIdAtContentPoint:contentPoint];
        [self setNeedsDisplay:YES];
        return;
    }
    if (self.draggingCanvas) {
        const CGFloat dx = viewPoint.x - self.lastViewDragPoint.x;
        const CGFloat dy = viewPoint.y - self.lastViewDragPoint.y;
        [self adjustPanByViewDeltaX:dx deltaY:dy];
        self.lastViewDragPoint = viewPoint;
        [self setNeedsDisplay:YES];
        return;
    }
    if (self.resizingSelection && (self.selectedNode || self.selectedSubgraph)) {
        NSRect nextFrame = self.resizeInitialFrame;
        if (self.selectedNode) {
            CGSize minimumSize = [self minimumSizeForNodeShape:self.selectedNode.shape];
            nextFrame = [self resizedRectFromInitialFrame:self.resizeInitialFrame
                                                  handle:self.activeResizeHandle
                                            currentPoint:contentPoint
                                             minimumSize:minimumSize
                                         lockAspectRatio:[self nodeShapeUsesLockedAspectRatio:self.selectedNode.shape]];
            nextFrame = [self clampedFrameForNodeRect:nextFrame shape:self.selectedNode.shape];
            [self applyFrame:nextFrame toNode:self.selectedNode];
        } else if (self.selectedSubgraph) {
            nextFrame = [self resizedRectFromInitialFrame:self.resizeInitialFrame
                                                  handle:self.activeResizeHandle
                                            currentPoint:contentPoint
                                             minimumSize:CGSizeMake(180.0, 120.0)
                                         lockAspectRatio:NO];
            NSRect previousFrame = [self frameForSubgraph:self.selectedSubgraph];
            nextFrame = [self clampedFrameForSubgraphRect:nextFrame subgraph:self.selectedSubgraph];
            [self applyFrame:nextFrame toSubgraph:self.selectedSubgraph previousFrame:previousFrame];
        }
        [self notifySelectionChanged];
        [self notifyDocumentMutation];
        [self setNeedsDisplay:YES];
        return;
    }

    if (!self.draggingSelection || (!self.selectedNode && !self.selectedSubgraph)) return;
    const CGFloat dx = contentPoint.x - self.lastDragContentPoint.x;
    const CGFloat dy = contentPoint.y - self.lastDragContentPoint.y;
    if (self.selectedNode) {
        self.selectedNode.x += dx;
        self.selectedNode.y += dy;
    } else if (self.selectedSubgraph) {
        NSString *selectedSubgraphId = self.selectedSubgraph.subgraphId ?: @"";
        self.selectedSubgraph.x += dx;
        self.selectedSubgraph.y += dy;
        self.selectedSubgraph.titleX += dx;
        self.selectedSubgraph.titleY += dy;

        for (MerrowFreeformNodeRecord *node in self.nodes) {
            NSString *parentId = node.parentSubgraphId;
            while (parentId.length > 0) {
                if ([parentId isEqualToString:selectedSubgraphId]) {
                    node.x += dx;
                    node.y += dy;
                    break;
                }
                parentId = self.subgraphsById[parentId].parentSubgraphId;
            }
        }

        for (MerrowFreeformSubgraphRecord *subgraph in self.subgraphs) {
            if (subgraph == self.selectedSubgraph) continue;
            NSString *parentId = subgraph.parentSubgraphId;
            while (parentId.length > 0) {
                if ([parentId isEqualToString:selectedSubgraphId]) {
                    subgraph.x += dx;
                    subgraph.y += dy;
                    subgraph.titleX += dx;
                    subgraph.titleY += dy;
                    break;
                }
                parentId = self.subgraphsById[parentId].parentSubgraphId;
            }
        }
    }
    self.lastDragContentPoint = contentPoint;
    [self notifyDocumentMutation];
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    if (self.draggingEdgeEndpoint && self.selectedEdge) {
        NSString *hoverObjectId = self.edgeDragHoverObjectId;
        if (hoverObjectId.length > 0) {
            if (self.activeEdgeEndpointHandle == MerrowFreeformEdgeEndpointHandleSource) {
                self.selectedEdge.sourceId = hoverObjectId;
            } else if (self.activeEdgeEndpointHandle == MerrowFreeformEdgeEndpointHandleTarget) {
                self.selectedEdge.targetId = hoverObjectId;
            }
            [self notifySelectionChanged];
            [self notifyDocumentMutation];
            [self commitPendingUndoGroupIfNeeded];
        } else {
            self.selectedEdge.sourceId = self.edgeDragOriginalSourceId ?: self.selectedEdge.sourceId;
            self.selectedEdge.targetId = self.edgeDragOriginalTargetId ?: self.selectedEdge.targetId;
            [self discardPendingUndoGroup];
        }
        self.draggingEdgeEndpoint = NO;
        self.activeEdgeEndpointHandle = MerrowFreeformEdgeEndpointHandleNone;
        self.edgeDragHoverObjectId = nil;
        self.edgeDragOriginalSourceId = nil;
        self.edgeDragOriginalTargetId = nil;
        [self setNeedsDisplay:YES];
        return;
    }
    [self commitPendingUndoGroupIfNeeded];
    self.draggingSelection = NO;
    self.draggingCanvas = NO;
    self.resizingSelection = NO;
    self.activeResizeHandle = MerrowFreeformResizeHandleNone;
}

- (void)scrollWheel:(NSEvent *)event {
    if (fabs(event.scrollingDeltaY) >= fabs(event.scrollingDeltaX)) {
        const CGFloat factor = pow(1.01, -event.scrollingDeltaY);
        [self adjustZoomByFactor:factor];
    } else {
        [self adjustPanByViewDeltaX:-event.scrollingDeltaX deltaY:event.scrollingDeltaY];
    }
    [self setNeedsDisplay:YES];
}

- (void)magnifyWithEvent:(NSEvent *)event {
    [self adjustZoomByFactor:(1.0 + event.magnification)];
    [self setNeedsDisplay:YES];
}

- (void)handleMagnifyGesture:(NSMagnificationGestureRecognizer *)recognizer {
    if (recognizer.state == NSGestureRecognizerStateBegan || recognizer.state == NSGestureRecognizerStateChanged) {
        [self adjustZoomByFactor:(1.0 + recognizer.magnification)];
        recognizer.magnification = 0.0;
        [self setNeedsDisplay:YES];
    }
}

- (void)smartMagnifyWithEvent:(NSEvent *)event {
    (void)event;
    [self resetView];
    [self setNeedsDisplay:YES];
}

@end